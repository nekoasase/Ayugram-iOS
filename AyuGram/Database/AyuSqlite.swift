import Foundation
import sqlcipher

// MARK: - Thin SQLite wrapper for the AyuGram archive
//
// The tree ships `sqlcipher` (an objc_library with `module_name = "sqlcipher"`,
// see `submodules/sqlcipher/BUILD`), and Postbox already links it. Postbox's own
// `Postbox.Database` is public but only exposes `execute(_:)` via `sqlite3_exec`,
// so it cannot return rows or bind parameters — which a relational archive needs.
//
// Rather than patching upstream Postbox, the AyuGram archive carries this small
// self-contained wrapper. It deliberately mirrors the style of Postbox's
// SQLite.swift-derived `Database.swift`, and needs no third-party dependency.

/// A value that can be stored in, or read from, a SQLite column.
public enum AyuSqliteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

extension AyuSqliteValue {
    public var int64Value: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var int32Value: Int32? {
        guard let value = self.int64Value else { return nil }
        return Int32(truncatingIfNeeded: value)
    }

    public var boolValue: Bool? {
        guard let value = self.int64Value else { return nil }
        return value != 0
    }

    public var doubleValue: Double? {
        switch self {
        case .real(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var stringValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var dataValue: Data? {
        if case .blob(let value) = self { return value }
        return nil
    }
}

/// Error raised by the wrapper, carrying the SQLite message and the SQL involved.
public struct AyuSqliteError: Error, CustomStringConvertible {
    public let message: String
    public let sql: String?

    public init(message: String, sql: String? = nil) {
        self.message = message
        self.sql = sql
    }

    public var description: String {
        if let sql {
            return "AyuSqliteError: \(self.message) [sql: \(sql)]"
        }
        return "AyuSqliteError: \(self.message)"
    }
}

/// SQLite tells the library to copy bound data instead of referencing the
/// caller's buffer. Swift does not import the macro, so it is rebuilt here.
private let ayuSqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A prepared statement. Owns the underlying `sqlite3_stmt`.
final class AyuSqliteStatement {
    private var handle: OpaquePointer?

    init?(database: OpaquePointer?, sql: String) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        self.handle = statement
    }

    deinit {
        sqlite3_finalize(self.handle)
    }

    /// 1-based, matching SQLite's own binding indices.
    func bind(_ values: [AyuSqliteValue]) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null:
                sqlite3_bind_null(self.handle, index)
            case .integer(let number):
                sqlite3_bind_int64(self.handle, index, number)
            case .real(let number):
                sqlite3_bind_double(self.handle, index, number)
            case .text(let string):
                // SQLITE_TRANSIENT makes SQLite copy the string immediately.
                sqlite3_bind_text(self.handle, index, string, -1, ayuSqliteTransient)
            case .blob(let data):
                if data.isEmpty {
                    sqlite3_bind_zeroblob(self.handle, index, 0)
                } else {
                    data.withUnsafeBytes { buffer in
                        _ = sqlite3_bind_blob(self.handle, index, buffer.baseAddress, Int32(data.count), ayuSqliteTransient)
                    }
                }
            }
        }
    }

    func reset() {
        sqlite3_reset(self.handle)
        sqlite3_clear_bindings(self.handle)
    }

    /// Advances to the next row. Returns false once the statement is done.
    func step() -> Bool {
        return sqlite3_step(self.handle) == SQLITE_ROW
    }

    var columnCount: Int32 {
        return sqlite3_column_count(self.handle)
    }

    func columnName(at index: Int32) -> String {
        guard let name = sqlite3_column_name(self.handle, index) else { return "" }
        return String(cString: name)
    }

    func columnNames() -> [String] {
        return (0 ..< self.columnCount).map { self.columnName(at: $0) }
    }

    func value(at index: Int32) -> AyuSqliteValue {
        switch sqlite3_column_type(self.handle, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(self.handle, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(self.handle, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(self.handle, index) else { return .null }
            return .text(String(cString: text))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(self.handle, index))
            guard count > 0, let blob = sqlite3_column_blob(self.handle, index) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: blob, count: count))
        default:
            return .null
        }
    }
}

/// A connection to the AyuGram archive database.
public final class AyuSqlite {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "ayugram.sqlite")

    /// Opens (creating if needed) the database at `path`.
    public init?(path: String) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            if let handle {
                sqlite3_close(handle)
            }
            return nil
        }
        self.handle = handle

        // WAL matches the Android original; the archive is written while the
        // user is actively using the client.
        guard self.execute("PRAGMA journal_mode = WAL"),
              self.execute("PRAGMA foreign_keys = ON") else {
            sqlite3_close(handle)
            self.handle = nil
            return nil
        }
    }

    deinit {
        if let handle = self.handle {
            sqlite3_close(handle)
        }
    }

    public var lastError: String? {
        guard let handle = self.handle, let message = sqlite3_errmsg(handle) else {
            return nil
        }
        return String(cString: message)
    }

    /// Runs one or more statements, ignoring any result rows.
    @discardableResult
    public func execute(_ sql: String) -> Bool {
        guard let handle = self.handle else { return false }
        return sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    public func execute(_ sql: String) throws {
        guard self.execute(sql) else {
            throw AyuSqliteError(message: self.lastError ?? "unknown error", sql: sql)
        }
    }

    /// Rowid produced by the most recent successful INSERT.
    public var lastInsertRowId: Int64 {
        guard let handle = self.handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    /// Number of rows changed by the most recent statement.
    public var changes: Int32 {
        guard let handle = self.handle else { return 0 }
        return sqlite3_changes(handle)
    }

    /// Runs a statement that returns rows, as column-name keyed dictionaries.
    public func query(_ sql: String, _ bindings: [AyuSqliteValue] = []) throws -> [[String: AyuSqliteValue]] {
        guard let statement = AyuSqliteStatement(database: self.handle, sql: sql) else {
            throw AyuSqliteError(message: self.lastError ?? "could not prepare statement", sql: sql)
        }
        statement.bind(bindings)

        let names = statement.columnNames()
        var rows: [[String: AyuSqliteValue]] = []
        while statement.step() {
            var row: [String: AyuSqliteValue] = [:]
            for index in 0 ..< statement.columnCount {
                let name = names[Int(index)]
                row[name.isEmpty ? "column\(index)" : name] = statement.value(at: index)
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs a statement that does not return rows.
    public func run(_ sql: String, _ bindings: [AyuSqliteValue] = []) throws {
        guard let statement = AyuSqliteStatement(database: self.handle, sql: sql) else {
            throw AyuSqliteError(message: self.lastError ?? "could not prepare statement", sql: sql)
        }
        statement.bind(bindings)
        guard !statement.step() else {
            // A row came back where none was expected; drain it.
            while statement.step() {}
            return
        }
    }

    /// Runs `body` inside a transaction, rolling back on any thrown error.
    public func transaction<T>(_ body: (AyuSqlite) throws -> T) throws -> T {
        try self.execute("BEGIN IMMEDIATE")
        do {
            let result = try body(self)
            try self.execute("COMMIT")
            return result
        } catch {
            _ = self.execute("ROLLBACK")
            throw error
        }
    }

    /// Serialises access to the archive. The client writes snapshots from
    /// background queues while the UI reads them.
    public func sync<T>(_ body: () throws -> T) rethrows -> T {
        return try self.queue.sync(execute: body)
    }
}
