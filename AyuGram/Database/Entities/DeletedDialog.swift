import Foundation

/// A dialog (chat) that was removed from the user's list, kept so it can be
/// restored and inspected.
///
/// Mirrors `com.radolyn.ayugram.database.entities.DeletedDialog`.
/// `folderId` is nullable: it was added later by an Android migration
/// (`ALTER TABLE DeletedDialog ADD COLUMN folderId INTEGER DEFAULT NULL`).
public struct DeletedDialog: AyuTableRecord {
    public static let databaseTableName = "DeletedDialog"

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `nil` on insert lets SQLite assign the rowid.
    public var fakeId: Int64?
    public var userId: Int64
    public var dialogId: Int64
    public var peerId: Int64
    public var folderId: Int32?
    public var topMessage: Int32
    public var lastMessageDate: Int32
    public var flags: Int32
    public var entityCreateDate: Int64

    public enum CodingKeys: String, CodingKey, CaseIterable {
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

    public init(
        fakeId: Int64? = nil,
        userId: Int64,
        dialogId: Int64,
        peerId: Int64,
        folderId: Int32? = nil,
        topMessage: Int32,
        lastMessageDate: Int32,
        flags: Int32 = 0,
        entityCreateDate: Int64
    ) {
        self.fakeId = fakeId
        self.userId = userId
        self.dialogId = dialogId
        self.peerId = peerId
        self.folderId = folderId
        self.topMessage = topMessage
        self.lastMessageDate = lastMessageDate
        self.flags = flags
        self.entityCreateDate = entityCreateDate
    }
}
