import Foundation

// MARK: - Shared message snapshot
//
// Mirrors `com.radolyn.ayugram.database.entities.AyuMessageBase` from the
// Android original. `DeletedMessage` and `EditedMessage` carry an identical set
// of 35 columns (verified against the DEX DDL — see docs/raw-schema.sql), which
// is exactly why the Android code has a shared base entity. On iOS this is
// expressed as one generic record bound to a table, so the column list exists
// once and cannot drift between the two tables.
//
// Columns holding `BLOB` data carry serialized Telegram objects. The Android
// original serialises the `TLRPC` types (`replySerialized`, `documentSerialized`,
// `thumbsSerialized`, `documentAttributesSerialized`); on iOS the equivalent
// payloads are produced by the snapshot coder in Features/AntiDelete.

/// Table for messages deleted by any participant.
public enum AyuDeletedMessageTable: AyuTableKind {
    public static let databaseTableName = "DeletedMessage"
}

/// Table for previous revisions of edited messages.
public enum AyuEditedMessageTable: AyuTableKind {
    public static let databaseTableName = "EditedMessage"
}

/// A point-in-time snapshot of a message, stored in either archive table.
public struct AyuMessageRecord<Table: AyuTableKind>: AyuTableRecord {
    public static var databaseTableName: String { Table.databaseTableName }

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// Rowid. `nil` on insert lets SQLite assign it (`INTEGER PRIMARY KEY AUTOINCREMENT`).
    public var fakeId: Int64?

    public var userId: Int64
    public var dialogId: Int64
    public var groupedId: Int64
    public var peerId: Int64
    public var fromId: Int64
    public var topicId: Int64
    public var messageId: Int32
    public var date: Int32
    public var flags: Int32
    public var editDate: Int32
    public var views: Int32

    public var fwdFlags: Int32
    public var fwdFromId: Int64
    public var fwdName: String?
    public var fwdDate: Int32
    public var fwdPostAuthor: String?

    public var postAuthor: String?

    public var replyFlags: Int32
    public var replyMessageId: Int32
    public var replyPeerId: Int64
    public var replyTopId: Int32
    public var replyForumTopic: Bool
    public var replySerialized: Data?
    public var replyMarkupSerialized: Data?

    /// When this snapshot row was written (unix millis).
    public var entityCreateDate: Int64

    public var text: String?
    public var textEntities: Data?
    public var mediaPath: String?
    public var hqThumbPath: String?

    public var documentType: Int32
    public var documentSerialized: Data?
    public var thumbsSerialized: Data?
    public var documentAttributesSerialized: Data?
    public var mimeType: String?

    public enum CodingKeys: String, CodingKey, CaseIterable {
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

    public init(
        fakeId: Int64? = nil,
        userId: Int64,
        dialogId: Int64,
        groupedId: Int64 = 0,
        peerId: Int64,
        fromId: Int64 = 0,
        topicId: Int64 = 0,
        messageId: Int32,
        date: Int32,
        flags: Int32 = 0,
        editDate: Int32 = 0,
        views: Int32 = 0,
        fwdFlags: Int32 = 0,
        fwdFromId: Int64 = 0,
        fwdName: String? = nil,
        fwdDate: Int32 = 0,
        fwdPostAuthor: String? = nil,
        postAuthor: String? = nil,
        replyFlags: Int32 = 0,
        replyMessageId: Int32 = 0,
        replyPeerId: Int64 = 0,
        replyTopId: Int32 = 0,
        replyForumTopic: Bool = false,
        replySerialized: Data? = nil,
        replyMarkupSerialized: Data? = nil,
        entityCreateDate: Int64,
        text: String? = nil,
        textEntities: Data? = nil,
        mediaPath: String? = nil,
        hqThumbPath: String? = nil,
        documentType: Int32 = 0,
        documentSerialized: Data? = nil,
        thumbsSerialized: Data? = nil,
        documentAttributesSerialized: Data? = nil,
        mimeType: String? = nil
    ) {
        self.fakeId = fakeId
        self.userId = userId
        self.dialogId = dialogId
        self.groupedId = groupedId
        self.peerId = peerId
        self.fromId = fromId
        self.topicId = topicId
        self.messageId = messageId
        self.date = date
        self.flags = flags
        self.editDate = editDate
        self.views = views
        self.fwdFlags = fwdFlags
        self.fwdFromId = fwdFromId
        self.fwdName = fwdName
        self.fwdDate = fwdDate
        self.fwdPostAuthor = fwdPostAuthor
        self.postAuthor = postAuthor
        self.replyFlags = replyFlags
        self.replyMessageId = replyMessageId
        self.replyPeerId = replyPeerId
        self.replyTopId = replyTopId
        self.replyForumTopic = replyForumTopic
        self.replySerialized = replySerialized
        self.replyMarkupSerialized = replyMarkupSerialized
        self.entityCreateDate = entityCreateDate
        self.text = text
        self.textEntities = textEntities
        self.mediaPath = mediaPath
        self.hqThumbPath = hqThumbPath
        self.documentType = documentType
        self.documentSerialized = documentSerialized
        self.thumbsSerialized = thumbsSerialized
        self.documentAttributesSerialized = documentAttributesSerialized
        self.mimeType = mimeType
    }
}

/// Deleted messages, keyed to the table `DeletedMessage`.
public typealias DeletedMessage = AyuMessageRecord<AyuDeletedMessageTable>

/// Previous revisions of edited messages, keyed to the table `EditedMessage`.
public typealias EditedMessage = AyuMessageRecord<AyuEditedMessageTable>
