import Foundation
import GRDB

/// Reactions that were attached to a message at the moment it was deleted.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedMessageReaction`.
/// Rows are linked to their snapshot through `deletedMessageId` -> `DeletedMessage.fakeId`.
struct DeletedMessageReaction: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "DeletedMessageReaction"

    /// `nil` on insert lets SQLite assign the rowid.
    var fakeReactionId: Int64?
    var deletedMessageId: Int64
    var emoticon: String?
    var documentId: Int64
    var isCustom: Bool
    var count: Int32
    var selfSelected: Bool

    enum CodingKeys: String, CodingKey {
        case fakeReactionId = "fakeReactionId"
        case deletedMessageId = "deletedMessageId"
        case emoticon = "emoticon"
        case documentId = "documentId"
        case isCustom = "isCustom"
        case count = "count"
        case selfSelected = "selfSelected"
    }
}

extension DeletedMessageReaction {
    /// The snapshot this reaction belonged to.
    static let deletedMessage = belongsTo(
        DeletedMessage.self,
        using: ForeignKey(["deletedMessageId"])
    )
}

extension DeletedMessage {
    /// Reactions captured together with the snapshot.
    static let reactions = hasMany(
        DeletedMessageReaction.self,
        using: ForeignKey(["deletedMessageId"])
    )
}

/// A deleted message together with its reactions.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedMessageFull`. This is a
/// read-only projection, **not a table**: the APK contains no `CREATE TABLE` for
/// it (it is Room's `@Embedded`/`@Relation` aggregate). The verifier therefore
/// deliberately excludes it from the table cross-check.
struct DeletedMessageFull: Decodable, FetchableRecord {
    var message: DeletedMessage
    var reactions: [DeletedMessageReaction]

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case reactions = "reactions"
    }
}

extension DeletedMessageFull {
    /// Fetch snapshots with their reactions attached.
    static func request(limit: Int = 100) -> QueryInterfaceRequest<DeletedMessageFull> {
        DeletedMessage
            .including(all: DeletedMessage.reactions)
            .asRequest(of: DeletedMessageFull.self)
            .limit(limit)
    }
}
