import Foundation

// MARK: - Record contracts for the AyuGram archive
//
// The Android original uses Room, which maps entities to tables. On iOS the
// archive talks to SQLite through `AyuSqlite`, so the mapping is expressed as
// two small protocols. `CodingKeys` stays the single source of truth for the
// column mapping, which lets `tools/verify_models.py` cross-check every record
// against `schema.sql` without a Swift compiler.

/// Binds a record type to the table it lives in.
///
/// Mirrors the role of Room's `@Entity(tableName = ...)`. `DeletedMessage` and
/// `EditedMessage` share one generic record, so the table is a type parameter
/// rather than a constant — exactly like Android's shared `AyuMessageBase`.
public protocol AyuTableKind {
    static var databaseTableName: String { get }
}

/// A record that can be read from and written to one table.
public protocol AyuTableRecord: Codable {
    /// Table this record belongs to.
    static var databaseTableName: String { get }
    /// Columns in declaration order, used to build INSERT statements.
    static var columnNames: [String] { get }
}

extension AyuTableRecord {
    /// Fully qualified column list, e.g. `` `userId`, `dialogId` ``.
    public static var sqlColumnList: String {
        return self.columnNames.map { "`\($0)`" }.joined(separator: ", ")
    }

    /// Placeholder list matching ``sqlColumnList``.
    public static var sqlPlaceholders: String {
        return Array(repeating: "?", count: self.columnNames.count).joined(separator: ", ")
    }
}
