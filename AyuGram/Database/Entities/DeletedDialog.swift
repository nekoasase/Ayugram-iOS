import Foundation
import GRDB

/// A dialog (chat) that was removed from the user's list, kept so it can be
/// restored and inspected.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedDialog`.
/// `folderId` is nullable: it was added later by an Android migration
/// (`ALTER TABLE DeletedDialog ADD COLUMN folderId INTEGER DEFAULT NULL`).
struct DeletedDialog: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "DeletedDialog"

    /// `nil` on insert lets SQLite assign the rowid.
    var fakeId: Int64?
    var userId: Int64
    var dialogId: Int64
    var peerId: Int64
    var folderId: Int32?
    var topMessage: Int32
    var lastMessageDate: Int32
    var flags: Int32
    var entityCreateDate: Int64

    enum CodingKeys: String, CodingKey {
        case fakeId = "fakeId"
        case userId = "userId"
        case dialogId = "dialogId"
        case peerId = "peerId"
        case folderId = "folderId"
        case topMessage = "topMessage"
        case lastMessageDate = "lastMessageDate"
        case flags = "flags"
        case entityCreateDate = "entityCreateDate"
    }
}
