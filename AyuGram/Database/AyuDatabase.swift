import Foundation
import GRDB

/// AyuGram patch-layer database.
///
/// Mirrors `com.radolyn.ayugram.database.AyuDatabase` (Room) from the Android
/// original. Room tracked schema versions 23…32; on iOS a fresh installation
/// starts directly at the final v32 shape, and databases exported from Android
/// are upgraded separately (see `AyuAndroidImporter`).
///
/// Schema source of truth: `AyuGram/Database/Schema/schema.sql`,
/// generated into `AyuSchema.generated.swift`.
final class AyuDatabase {
    static let shared = AyuDatabase()

    /// Name of the database file inside the app container.
    static let fileName = "ayugram.sqlite"

    let writer: any DatabaseWriter

    /// Opens (creating if needed) the archive database at `path`.
    ///
    /// A corrupt archive must never take the client down, so on failure this
    /// falls back to an in-memory database and the app keeps running.
    init(path: String = AyuDatabase.defaultPath) {
        let writer = Self.openWriter(path: path)
        self.writer = writer
        do {
            try Self.migrator.migrate(writer)
        } catch {
            assertionFailure("AyuDatabase migration failed: \(error)")
        }
    }

    /// In-memory instance for tests and SwiftUI previews.
    init(inMemory: Bool) {
        let writer = try! DatabaseQueue()
        self.writer = writer
        try! Self.migrator.migrate(writer)
    }

    private static func openWriter(path: String) -> any DatabaseWriter {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // WAL matches the Android original and keeps large archive writes
            // off the reader's critical path.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        do {
            return try DatabasePool(path: path, configuration: configuration)
        } catch {
            assertionFailure("AyuDatabase could not open \(path): \(error)")
            return try! DatabaseQueue()
        }
    }

    static var defaultPath: String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(fileName).path
    }

    // MARK: - Migrations

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Match Room's discipline: never silently wipe user data on a schema
        // mismatch. A broken archive is reported, not destroyed.
        migrator.eraseDatabaseOnSchemaChange = false

        // v1 == AyuGram Android schema version 32.
        migrator.registerMigration("v1_ayuInitial") { db in
            for statement in AyuSchema.createStatements {
                try db.execute(sql: statement)
            }
        }

        return migrator
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
enum AyuAndroidImporter {
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

    /// True when `db` still carries the pre-rebuild `RegexFilter` shape.
    static func needsRegexFilterRebuild(_ db: Database) throws -> Bool {
        let columns = try db.columns(in: "RegexFilter").map(\.name)
        return columns.contains("fakeId") && !columns.contains("id")
    }

    /// Brings an imported Android database up to the current schema.
    ///
    /// Every step is guarded, so the upgrade is safe to re-run and safe on a
    /// database that is already partly migrated.
    static func upgrade(_ db: Database) throws {
        func apply(_ additions: [(table: String, column: String, statement: String)]) throws {
            for addition in additions {
                let existing = try db.columns(in: addition.table).map(\.name)
                if !existing.contains(addition.column) {
                    try db.execute(sql: addition.statement)
                }
            }
        }

        try apply(preRebuildAdditions)

        if try needsRegexFilterRebuild(db) {
            for statement in regexFilterRebuildStatements {
                try db.execute(sql: statement)
            }
        }

        try apply(postRebuildAdditions)
    }
}
