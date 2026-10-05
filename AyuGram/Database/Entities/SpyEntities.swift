import Foundation

// MARK: - Spy: who read what
//
// Mirrors `com.radolyn.ayugram.database.entities.SpyMessageRead` and
// `SpyMessageContentsRead`. The Android original keeps two separate tables
// because Telegram reports two distinct events:
//
//   * `updateReadMessagesContents` / `updateChannelReadMessagesContents`
//     -> the *contents* were read          -> SpyMessageContentsRead
//   * read marks / read participants
//     -> the message was read              -> SpyMessageRead
//
// Both tables share the same shape, so they are expressed as one generic record
// bound to a table, mirroring the shared-entity approach used for snapshots.

/// Message was read.
public enum AyuSpyMessageReadTable: AyuTableKind {
    public static let databaseTableName = "SpyMessageRead"
}

/// Message contents were read.
public enum AyuSpyMessageContentsReadTable: AyuTableKind {
    public static let databaseTableName = "SpyMessageContentsRead"
}

/// One "user X read message Y in dialog Z" observation.
public struct AyuSpyRecord<Table: AyuTableKind>: AyuTableRecord {
    public static var databaseTableName: String { Table.databaseTableName }

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `nil` on insert lets SQLite assign the rowid.
    public var fakeId: Int64?
    public var userId: Int64
    /// Negative for channels/supergroups (`-100…`), hence 64-bit.
    public var dialogId: Int64
    public var messageId: Int32
    /// When this observation was recorded (unix millis).
    public var entityCreateDate: Int64

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case fakeId = "fakeId"
        case userId = "userId"
        case dialogId = "dialogId"
        case messageId = "messageId"
        case entityCreateDate = "entityCreateDate"
    }

    public init(
        fakeId: Int64? = nil,
        userId: Int64,
        dialogId: Int64,
        messageId: Int32,
        entityCreateDate: Int64
    ) {
        self.fakeId = fakeId
        self.userId = userId
        self.dialogId = dialogId
        self.messageId = messageId
        self.entityCreateDate = entityCreateDate
    }
}

/// Message was read, keyed to the table `SpyMessageRead`.
public typealias SpyMessageRead = AyuSpyRecord<AyuSpyMessageReadTable>

/// Message contents were read, keyed to the table `SpyMessageContentsRead`.
public typealias SpyMessageContentsRead = AyuSpyRecord<AyuSpyMessageContentsReadTable>
