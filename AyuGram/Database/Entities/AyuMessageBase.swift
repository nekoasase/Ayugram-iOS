import Foundation
import GRDB

// MARK: - Shared message snapshot
//
// Mirrors `com.radolyn.ayugram.database.entities.AyuMessageBase` from the
// Android original. `DeletedMessage` and `EditedMessage` carry an identical set
// of 35 columns (verified against the DEX DDL — see docs/raw-schema.sql), which
// is exactly why the Android code has a shared base entity. On iOS this is
// expressed as one generic record bound to a table, so the column list exists
// once and cannot drift between the two tables.
//
// Columns that hold `BLOB` data carry serialized Telegram objects. The Android
// original serialises the `TLRPC` types (`replySerialized`, `documentSerialized`,
// `thumbsSerialized`, `documentAttributesSerialized`); on iOS the equivalent
// payloads are produced by `AyuMessageSnapshotCoder` (see Features/AntiDelete).

/// Which archive table a snapshot record lives in.
protocol AyuMessageTableKind: TableRecord {
    static var databaseTableName: String { get }
}

/// Table for messages deleted by any participant.
enum AyuDeletedMessageTable: AyuMessageTableKind {
    static let databaseTableName = "DeletedMessage"
}

/// Table for previous revisions of edited messages.
enum AyuEditedMessageTable: AyuMessageTableKind {
    static let databaseTableName = "EditedMessage"
}

/// A point-in-time snapshot of a message, stored in either archive table.
struct AyuMessageRecord<Table: AyuMessageTableKind>: Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { Table.databaseTableName }

    /// Rowid. `nil` on insert lets SQLite assign it (`INTEGER PRIMARY KEY AUTOINCREMENT`).
    var fakeId: Int64?

    var userId: Int64
    var dialogId: Int64
    var groupedId: Int64
    var peerId: Int64
    var fromId: Int64
    var topicId: Int64
    var messageId: Int32
    var date: Int32
    var flags: Int32
    var editDate: Int32
    var views: Int32

    var fwdFlags: Int32
    var fwdFromId: Int64
    var fwdName: String?
    var fwdDate: Int32
    var fwdPostAuthor: String?

    var postAuthor: String?

    var replyFlags: Int32
    var replyMessageId: Int32
    var replyPeerId: Int64
    var replyTopId: Int32
    var replyForumTopic: Bool
    var replySerialized: Data?
    var replyMarkupSerialized: Data?

    /// When this snapshot row was written (unix millis).
    var entityCreateDate: Int64

    var text: String?
    var textEntities: Data?
    var mediaPath: String?
    var hqThumbPath: String?

    var documentType: Int32
    var documentSerialized: Data?
    var thumbsSerialized: Data?
    var documentAttributesSerialized: Data?
    var mimeType: String?

    enum CodingKeys: String, CodingKey {
        case fakeId = "fakeId"
        case userId = "userId"
        case dialogId = "dialogId"
        case groupedId = "groupedId"
        case peerId = "peerId"
        case fromId = "fromId"
        case topicId = "topicId"
        case messageId = "messageId"
        case date = "date"
        case flags = "flags"
        case editDate = "editDate"
        case views = "views"
        case fwdFlags = "fwdFlags"
        case fwdFromId = "fwdFromId"
        case fwdName = "fwdName"
        case fwdDate = "fwdDate"
        case fwdPostAuthor = "fwdPostAuthor"
        case postAuthor = "postAuthor"
        case replyFlags = "replyFlags"
        case replyMessageId = "replyMessageId"
        case replyPeerId = "replyPeerId"
        case replyTopId = "replyTopId"
        case replyForumTopic = "replyForumTopic"
        case replySerialized = "replySerialized"
        case replyMarkupSerialized = "replyMarkupSerialized"
        case entityCreateDate = "entityCreateDate"
        case text = "text"
        case textEntities = "textEntities"
        case mediaPath = "mediaPath"
        case hqThumbPath = "hqThumbPath"
        case documentType = "documentType"
        case documentSerialized = "documentSerialized"
        case thumbsSerialized = "thumbsSerialized"
        case documentAttributesSerialized = "documentAttributesSerialized"
        case mimeType = "mimeType"
    }
}

/// Deleted messages, keyed to the table `DeletedMessage`.
typealias DeletedMessage = AyuMessageRecord<AyuDeletedMessageTable>

/// Previous revisions of edited messages, keyed to the table `EditedMessage`.
typealias EditedMessage = AyuMessageRecord<AyuEditedMessageTable>
