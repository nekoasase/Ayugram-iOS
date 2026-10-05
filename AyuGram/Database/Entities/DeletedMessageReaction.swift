import Foundation

/// Reactions that were attached to a message at the moment it was deleted.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedMessageReaction`.
/// Rows are linked to their snapshot through `deletedMessageId` -> `DeletedMessage.fakeId`.
public struct DeletedMessageReaction: AyuTableRecord {
    public static let databaseTableName = "DeletedMessageReaction"

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `nil` on insert lets SQLite assign the rowid.
    public var fakeReactionId: Int64?
    public var deletedMessageId: Int64
    public var emoticon: String?
    public var documentId: Int64
    public var isCustom: Bool
    public var count: Int32
    public var selfSelected: Bool

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case fakeReactionId = "fakeReactionId"
        case deletedMessageId = "deletedMessageId"
        case emoticon = "emoticon"
        case documentId = "documentId"
        case isCustom = "isCustom"
        case count = "count"
        case selfSelected = "selfSelected"
    }

    public init(
        fakeReactionId: Int64? = nil,
        deletedMessageId: Int64,
        emoticon: String? = nil,
        documentId: Int64 = 0,
        isCustom: Bool = false,
        count: Int32 = 0,
        selfSelected: Bool = false
    ) {
        self.fakeReactionId = fakeReactionId
        self.deletedMessageId = deletedMessageId
        self.emoticon = emoticon
        self.documentId = documentId
        self.isCustom = isCustom
        self.count = count
        self.selfSelected = selfSelected
    }
}

/// A deleted message together with its reactions.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedMessageFull`. This is a
/// read-only projection, **not a table**: the APK contains no `CREATE TABLE` for
/// it (in Android it is Room's `@Embedded`/`@Relation` aggregate). The verifier
/// therefore deliberately excludes it from the table cross-check.
///
/// GRDB's `hasMany`/`belongsTo` associations are not available here, so the
/// relation is expressed as the join predicate below and executed by the DAO.
public struct DeletedMessageFull {
    public var message: DeletedMessage
    public var reactions: [DeletedMessageReaction]

    public init(message: DeletedMessage, reactions: [DeletedMessageReaction]) {
        self.message = message
        self.reactions = reactions
    }
}

extension DeletedMessageFull {
    /// Reactions for a batch of snapshots, keyed by `deletedMessageId`.
    ///
    /// Batching avoids the N+1 query the relation would otherwise cause when a
    /// chat with many deleted messages is opened.
    public static func reactionsQuery(forSnapshotCount count: Int) -> String {
        let placeholders = Array(repeating: "?", count: max(count, 1)).joined(separator: ", ")
        return "SELECT * FROM `DeletedMessageReaction` WHERE `deletedMessageId` IN (\(placeholders))"
    }
}
