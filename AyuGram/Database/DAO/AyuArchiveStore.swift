import Foundation

/// Read/write access to the AyuGram archive.
///
/// Mirrors the DAO layer of the Android original
/// (`com.radolyn.ayugram.database.dao.*`): `DeletedMessageDao`,
/// `EditedMessageDao`, `SpyDao`, `RegexFilterDao`, `DeletedDialogDao` are folded
/// into one store because the queries are few and the SQL reads better in one
/// place than spread across five files.
///
/// The mechanical work — mapping a row to a record and a record to bind values —
/// is generated (`Database/DAO/AyuRecords.generated.swift`); only the queries
/// live here.
public final class AyuArchiveStore {
    private let database: AyuDatabase

    public init(database: AyuDatabase = .shared) {
        self.database = database
    }

    private var sqlite: AyuSqlite {
        return self.database.sqlite
    }

    // MARK: - Generic access

    /// Inserts a record and returns its rowid.
    @discardableResult
    public func insert<R: AyuTableRecord>(_ record: R) throws -> Int64 {
        try self.sqlite.run(R.sqlInsert, record.sqlValues)
        return self.sqlite.lastInsertRowId
    }

    /// Runs a query and decodes every row into `R`.
    public func fetch<R: AyuTableRecord>(
        _ type: R.Type,
        _ sql: String,
        _ arguments: [AyuSqliteValue] = []
    ) throws -> [R] {
        return try self.sqlite.query(sql, arguments).map { R(row: $0) }
    }

    // MARK: - Anti-delete: DeletedMessage

    /// Snapshots for one dialog, newest first.
    public func deletedMessages(
        accountId: Int64,
        dialogId: Int64,
        limit: Int = 100,
        beforeMessageId: Int32? = nil
    ) throws -> [DeletedMessage] {
        var sql = """
            SELECT * FROM `DeletedMessage`
            WHERE `userId` = ? AND `dialogId` = ?
            """
        var arguments: [AyuSqliteValue] = [.integer(accountId), .integer(dialogId)]
        if let beforeMessageId = beforeMessageId {
            sql += " AND `messageId` < ?"
            arguments.append(.integer(Int64(beforeMessageId)))
        }
        sql += " ORDER BY `messageId` DESC LIMIT ?"
        arguments.append(.integer(Int64(limit)))
        return try self.fetch(DeletedMessage.self, sql, arguments)
    }

    /// Which of `messageIds` are present in the archive.
    ///
    /// Used to mark messages in a chat as "deleted, kept locally", so the batch
    /// is one query instead of one per message.
    public func archivedMessageIds(
        accountId: Int64,
        dialogId: Int64,
        messageIds: [Int32]
    ) throws -> Set<Int32> {
        guard !messageIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: messageIds.count).joined(separator: ", ")
        let sql = """
            SELECT `messageId` FROM `DeletedMessage`
            WHERE `userId` = ? AND `dialogId` = ? AND `messageId` IN (\(placeholders))
            """
        let arguments: [AyuSqliteValue] = [.integer(accountId), .integer(dialogId)]
            + messageIds.map { .integer(Int64($0)) }
        let rows = try self.sqlite.query(sql, arguments)
        return Set(rows.compactMap { $0["messageId"]?.int32Value })
    }

    /// Reactions captured with the given snapshots, keyed by snapshot rowid.
    public func reactions(forDeletedMessageIds ids: [Int64]) throws -> [Int64: [DeletedMessageReaction]] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let sql = "SELECT * FROM `DeletedMessageReaction` WHERE `deletedMessageId` IN (\(placeholders))"
        let reactions = try self.fetch(DeletedMessageReaction.self, sql, ids.map { .integer($0) })
        return Dictionary(grouping: reactions, by: { $0.deletedMessageId })
    }

    /// Snapshots with their reactions attached.
    public func deletedMessagesFull(
        accountId: Int64,
        dialogId: Int64,
        limit: Int = 100
    ) throws -> [DeletedMessageFull] {
        let messages = try self.deletedMessages(accountId: accountId, dialogId: dialogId, limit: limit)
        let ids = messages.compactMap(\.fakeId)
        let reactions = try self.reactions(forDeletedMessageIds: ids)
        return messages.map { message in
            DeletedMessageFull(
                message: message,
                reactions: message.fakeId.flatMap { reactions[$0] } ?? []
            )
        }
    }

    /// Drops snapshots recorded before `date`, keeping the archive bounded.
    public func pruneDeletedMessages(accountId: Int64, olderThan date: Int64) throws -> Int32 {
        try self.sqlite.run(
            "DELETE FROM `DeletedMessage` WHERE `userId` = ? AND `entityCreateDate` < ?",
            [.integer(accountId), .integer(date)]
        )
        return self.sqlite.changes
    }

    public func deletedMessageCount(accountId: Int64) throws -> Int32 {
        let rows = try self.sqlite.query(
            "SELECT COUNT(*) AS `count` FROM `DeletedMessage` WHERE `userId` = ?",
            [.integer(accountId)]
        )
        return rows.first?["count"]?.int32Value ?? 0
    }

    // MARK: - Anti-delete: DeletedDialog

    public func deletedDialogs(accountId: Int64, limit: Int = 200) throws -> [DeletedDialog] {
        try self.fetch(
            DeletedDialog.self,
            """
            SELECT * FROM `DeletedDialog`
            WHERE `userId` = ?
            ORDER BY `lastMessageDate` DESC LIMIT ?
            """,
            [.integer(accountId), .integer(Int64(limit))]
        )
    }

    // MARK: - Edited history

    /// Every stored revision of one message, oldest first.
    ///
    /// The Android schema indexes `(userId, dialogId, messageId, entityCreateDate)`,
    /// which is exactly this access path.
    public func editedHistory(
        accountId: Int64,
        dialogId: Int64,
        messageId: Int32
    ) throws -> [EditedMessage] {
        try self.fetch(
            EditedMessage.self,
            """
            SELECT * FROM `EditedMessage`
            WHERE `userId` = ? AND `dialogId` = ? AND `messageId` = ?
            ORDER BY `entityCreateDate` ASC
            """,
            [.integer(accountId), .integer(dialogId), .integer(Int64(messageId))]
        )
    }

    public func editedMessageIds(
        accountId: Int64,
        dialogId: Int64,
        messageIds: [Int32]
    ) throws -> Set<Int32> {
        guard !messageIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: messageIds.count).joined(separator: ", ")
        let rows = try self.sqlite.query(
            """
            SELECT DISTINCT `messageId` FROM `EditedMessage`
            WHERE `userId` = ? AND `dialogId` = ? AND `messageId` IN (\(placeholders))
            """,
            [.integer(accountId), .integer(dialogId)] + messageIds.map { .integer(Int64($0)) }
        )
        return Set(rows.compactMap { $0["messageId"]?.int32Value })
    }

    public func pruneEditedMessages(accountId: Int64, olderThan date: Int64) throws -> Int32 {
        try self.sqlite.run(
            "DELETE FROM `EditedMessage` WHERE `userId` = ? AND `entityCreateDate` < ?",
            [.integer(accountId), .integer(date)]
        )
        return self.sqlite.changes
    }

    // MARK: - Spy: who read what
    //
    // NOTE ON `userId`: unlike `DeletedMessage`, the spy tables carry a single
    // `userId` column and it holds the **reader**, not the account. That is the
    // only reading under which the recovered DAO query
    // (`SELECT * FROM spymessageread WHERE userId = ? AND dialogId = ? AND messageId = ?`)
    // selects anything meaningful: with `userId` as the account there would be
    // no reader recorded at all. The archive is per account — AyuGram's own
    // documentation describes the files as `ayu-data*`, per account — so the
    // account is not stored in these tables.
    //
    // This is an inference from the recovered DDL and SQL, not from the original
    // source: the release APK is built on exteraGram and its matching source tree
    // has not been located yet (AyuGram/AyuGram4A is the older Java line and has
    // no Spy tables). It is listed as such in docs/PORT-MAP.md.

    /// Users observed reading a message, oldest observation first.
    public func readersOfMessage(dialogId: Int64, messageId: Int32) throws -> [SpyMessageRead] {
        try self.fetch(
            SpyMessageRead.self,
            """
            SELECT * FROM `SpyMessageRead`
            WHERE `dialogId` = ? AND `messageId` = ?
            ORDER BY `entityCreateDate` ASC
            """,
            [.integer(dialogId), .integer(Int64(messageId))]
        )
    }

    /// Distinct user ids that read a message's *contents*.
    ///
    /// Kept separate because Telegram reports content reads
    /// (`updateReadMessagesContents`) independently of read marks.
    public func contentReaderIds(dialogId: Int64, messageId: Int32) throws -> [Int64] {
        let rows = try self.sqlite.query(
            """
            SELECT DISTINCT `userId` FROM `SpyMessageContentsRead`
            WHERE `dialogId` = ? AND `messageId` = ?
            """,
            [.integer(dialogId), .integer(Int64(messageId))]
        )
        return rows.compactMap { $0["userId"]?.int64Value }
    }

    /// Whether this reader is already recorded for the message.
    ///
    /// Read receipts repeat, so this guard keeps the table from growing without
    /// bound. It mirrors the Android DAO's lookup before insert.
    public func hasReader(dialogId: Int64, messageId: Int32, readerId: Int64) throws -> Bool {
        let rows = try self.sqlite.query(
            """
            SELECT 1 AS `present` FROM `SpyMessageRead`
            WHERE `userId` = ? AND `dialogId` = ? AND `messageId` = ?
            LIMIT 1
            """,
            [.integer(readerId), .integer(dialogId), .integer(Int64(messageId))]
        )
        return !rows.isEmpty
    }

    /// Records that `readerId` read a message. Returns false if already known.
    @discardableResult
    public func recordRead(
        dialogId: Int64,
        messageId: Int32,
        readerId: Int64,
        date: Int64
    ) throws -> Bool {
        if try self.hasReader(dialogId: dialogId, messageId: messageId, readerId: readerId) {
            return false
        }
        try self.insert(
            SpyMessageRead(
                userId: readerId,
                dialogId: dialogId,
                messageId: messageId,
                entityCreateDate: date
            )
        )
        return true
    }

    public func pruneSpyRecords(olderThan date: Int64) throws -> Int32 {
        try self.sqlite.run(
            "DELETE FROM `SpyMessageRead` WHERE `entityCreateDate` < ?",
            [.integer(date)]
        )
        let removed = self.sqlite.changes
        try self.sqlite.run(
            "DELETE FROM `SpyMessageContentsRead` WHERE `entityCreateDate` < ?",
            [.integer(date)]
        )
        return removed + self.sqlite.changes
    }

    // MARK: - Regex filters

    /// Filters that apply to a dialog: its own, plus global ones minus exclusions.
    public func applicableFilters(dialogId: Int64) throws -> [RegexFilter] {
        try self.fetch(
            RegexFilter.self,
            RegexFilter.applicableQuery,
            [.integer(dialogId), .integer(dialogId)]
        )
    }

    public func allFilters() throws -> [RegexFilter] {
        try self.fetch(
            RegexFilter.self,
            "\(RegexFilter.sqlSelectAll) ORDER BY `enabled` DESC, `text` ASC"
        )
    }

    @discardableResult
    public func saveFilter(_ filter: RegexFilter) throws -> Int64 {
        try self.sqlite.run(
            """
            INSERT INTO `RegexFilter` (`id`, `text`, `enabled`, `reversed`, `caseInsensitive`, `dialogId`)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(`id`) DO UPDATE SET
                `text` = excluded.`text`,
                `enabled` = excluded.`enabled`,
                `reversed` = excluded.`reversed`,
                `caseInsensitive` = excluded.`caseInsensitive`,
                `dialogId` = excluded.`dialogId`
            """,
            filter.sqlValues
        )
        return self.sqlite.lastInsertRowId
    }

    @discardableResult
    public func deleteFilter(id: Data) throws -> Int32 {
        try self.sqlite.run("DELETE FROM `RegexFilter` WHERE `id` = ?", [.blob(id)])
        return self.sqlite.changes
    }

    public func setFilterEnabled(id: Data, enabled: Bool) throws {
        try self.sqlite.run(
            "UPDATE `RegexFilter` SET `enabled` = ? WHERE `id` = ?",
            [.integer(enabled ? 1 : 0), .blob(id)]
        )
    }

    @discardableResult
    public func excludeFilter(id: Data, from dialogId: Int64) throws -> Int64 {
        try self.insert(RegexFilterGlobalExclusion(dialogId: dialogId, filterId: id))
    }

    public func removeExclusion(filterId: Data, dialogId: Int64) throws {
        try self.sqlite.run(
            "DELETE FROM `RegexFilterGlobalExclusion` WHERE `filterId` = ? AND `dialogId` = ?",
            [.blob(filterId), .integer(dialogId)]
        )
    }
}
