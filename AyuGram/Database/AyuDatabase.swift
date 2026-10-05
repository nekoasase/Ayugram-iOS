import Foundation

/// AyuGram patch-layer database.
///
/// Mirrors `com.radolyn.ayugram.database.AyuDatabase` (Room) from the Android
/// original, and deliberately reuses Room's version numbering: a fresh install
/// is stamped with `PRAGMA user_version = 32`, which is exactly the version
/// AyuGram for Android reached. That makes an archive exported from Android
/// importable — its `user_version` tells us which upgrade steps are still owed.
///
/// Storage is the in-tree `sqlcipher` through `AyuSqlite`. GRDB was rejected:
/// it is not vendored in this repository, and the alternative Postbox store is
/// key-value based, which cannot express the relational schema recovered from
/// the APK (`schema.sql`, verified by `tools/verify_schema.py`).
public final class AyuDatabase {
    /// Shared instance used by the app.
    public static let shared = AyuDatabase()

    /// Name of the database file inside the app container.
    public static let fileName = "ayugram.sqlite"

    /// Schema version, matching AyuGram for Android's final Room version.
    public static let schemaVersion: Int32 = 32

    public let sqlite: AyuSqlite

    /// Opens (creating if needed) the archive database at `path`.
    public init(path: String = AyuDatabase.defaultPath) {
        self.sqlite = AyuSqlite(path: path) ?? AyuSqlite(path: ":memory:")!
        do {
            try self.migrate()
        } catch {
            assertionFailure("AyuDatabase migration failed: \(error)")
        }
    }

    /// In-memory instance for tests and previews.
    public init(inMemory: Bool) {
        self.sqlite = AyuSqlite(path: ":memory:")!
        do {
            try self.migrate()
        } catch {
            assertionFailure("AyuDatabase migration failed: \(error)")
        }
    }

    public static var defaultPath: String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(fileName).path
    }

    // MARK: - Migrations

    /// `PRAGMA user_version`, the same slot Room uses to record its schema version.
    public var userVersion: Int32 {
        get {
            let rows = (try? self.sqlite.query("PRAGMA user_version")) ?? []
            return rows.first?["user_version"]?.int32Value ?? 0
        }
        set {
            try? self.sqlite.execute("PRAGMA user_version = \(newValue)")
        }
    }

    private func migrate() throws {
        let version = self.userVersion

        if version == 0 {
            // Fresh installation: create the final (v32-equivalent) schema.
            try self.sqlite.transaction { connection in
                for statement in AyuSchema.createStatements {
                    try connection.execute(statement)
                }
            }
            self.userVersion = Self.schemaVersion
            return
        }

        if version < Self.schemaVersion {
            // An archive produced by AyuGram for Android at an older Room version.
            try self.sqlite.transaction { connection in
                try AyuAndroidImporter.upgrade(connection)
            }
            self.userVersion = Self.schemaVersion
        }
    }
}

/// Upgrades a database file exported from Android AyuGram.
///
/// The Android original may hand us a file at any Room version from 23 to 32.
/// The statements below are recovered verbatim from the APK (see
/// `docs/raw-schema.sql`); they are only needed when importing an old archive,
/// never for a fresh install.
///
/// **Order is not arbitrary.** `RegexFilter` moved from an INTEGER `fakeId`
/// primary key to a BLOB `id` primary key, which Room implemented as a full
/// table rebuild. The rebuild's replacement table is created *without* the
/// `reversed` column and its `INSERT ... SELECT` copies only
/// `text/enabled/caseInsensitive/dialogId`. The final schema does contain
/// `reversed`, so the only consistent history is: **rebuild first, then add
/// `reversed`**. Applying the two in the other order silently drops the flag
/// (this exact bug was caught by `tools/verify_importer.py`).
public enum AyuAndroidImporter {
    /// `ALTER TABLE ... ADD COLUMN` applied before the RegexFilter rebuild.
    static let preRebuildAdditions: [(table: String, column: String, statement: String)] = [
        ("DeletedDialog", "folderId",
         "ALTER TABLE `DeletedDialog` ADD COLUMN `folderId` INTEGER DEFAULT NULL"),
        ("DeletedMessage", "postAuthor",
         "ALTER TABLE `DeletedMessage` ADD COLUMN `postAuthor` TEXT DEFAULT NULL"),
        ("DeletedMessage", "replySerialized",
         "ALTER TABLE `DeletedMessage` ADD COLUMN `replySerialized` BLOB DEFAULT NULL"),
        ("DeletedMessage", "replyMarkupSerialized",
         "ALTER TABLE `DeletedMessage` ADD COLUMN `replyMarkupSerialized` BLOB DEFAULT NULL"),
        ("EditedMessage", "postAuthor",
         "ALTER TABLE `EditedMessage` ADD COLUMN `postAuthor` TEXT DEFAULT NULL"),
        ("EditedMessage", "replySerialized",
         "ALTER TABLE `EditedMessage` ADD COLUMN `replySerialized` BLOB DEFAULT NULL"),
        ("EditedMessage", "replyMarkupSerialized",
         "ALTER TABLE `EditedMessage` ADD COLUMN `replyMarkupSerialized` BLOB DEFAULT NULL"),
    ]

    /// The table rebuild Room performed for `RegexFilter`.
    ///
    /// Old rows carry no stable UUID, so one is generated at import time.
    static let regexFilterRebuildStatements: [String] = [
        "CREATE TABLE IF NOT EXISTS `RegexFilter_new` (`id` BLOB PRIMARY KEY NOT NULL, "
            + "`text` TEXT, `enabled` INTEGER NOT NULL, `caseInsensitive` INTEGER NOT NULL, "
            + "`dialogId` INTEGER)",
        "INSERT OR IGNORE INTO `RegexFilter_new` (`id`, `text`, `enabled`, `caseInsensitive`, `dialogId`) "
            + "SELECT randomblob(16), `text`, `enabled`, `caseInsensitive`, `dialogId` FROM `RegexFilter`",
        "DROP TABLE `RegexFilter`",
        "ALTER TABLE `RegexFilter_new` RENAME TO `RegexFilter`",
    ]

    /// Applied only after the RegexFilter rebuild produced the BLOB-PK table.
    static let postRebuildAdditions: [(table: String, column: String, statement: String)] = [
        ("RegexFilter", "reversed",
         "ALTER TABLE `RegexFilter` ADD COLUMN `reversed` INTEGER NOT NULL DEFAULT false"),
    ]

    /// Column names currently present in `table`.
    static func columns(of table: String, in connection: AyuSqlite) throws -> Set<String> {
        let rows = try connection.query("PRAGMA table_info(`\(table)`)")
        return Set(rows.compactMap { $0["name"]?.stringValue })
    }

    /// True when `connection` still carries the pre-rebuild `RegexFilter` shape.
    static func needsRegexFilterRebuild(_ connection: AyuSqlite) throws -> Bool {
        let columns = try self.columns(of: "RegexFilter", in: connection)
        return columns.contains("fakeId") && !columns.contains("id")
    }

    /// Brings an imported Android database up to the current schema.
    ///
    /// Every step is guarded, so the upgrade is safe to re-run and safe on a
    /// database that is already partly migrated.
    public static func upgrade(_ connection: AyuSqlite) throws {
        func apply(_ additions: [(table: String, column: String, statement: String)]) throws {
            for addition in additions {
                let existing = try self.columns(of: addition.table, in: connection)
                if !existing.contains(addition.column) {
                    try connection.execute(addition.statement)
                }
            }
        }

        try apply(preRebuildAdditions)

        if try self.needsRegexFilterRebuild(connection) {
            for statement in regexFilterRebuildStatements {
                try connection.execute(statement)
            }
        }

        try apply(postRebuildAdditions)
    }
}
