import Foundation
import GRDB

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
// bound to a table.

/// Which spy table a record lives in.
protocol AyuSpyTableKind: TableRecord {
    static var databaseTableName: String { get }
}

/// Message was read.
enum AyuSpyMessageReadTable: AyuSpyTableKind {
    static let databaseTableName = "SpyMessageRead"
}

/// Message contents were read.
enum AyuSpyMessageContentsReadTable: AyuSpyTableKind {
    static let databaseTableName = "SpyMessageContentsRead"
}

/// One "user X read message Y in dialog Z" observation.
struct AyuSpyRecord<Table: AyuSpyTableKind>: Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { Table.databaseTableName }

    /// `nil` on insert lets SQLite assign the rowid.
    var fakeId: Int64?
    var userId: Int64
    /// Negative for channels/supergroups (`-100…`), hence 64-bit.
    var dialogId: Int64
    var messageId: Int32
    /// When this observation was recorded (unix millis).
    var entityCreateDate: Int64

    enum CodingKeys: String, CodingKey {
        case fakeId = "fakeId"
        case userId = "userId"
        case dialogId = "dialogId"
        case messageId = "messageId"
        case entityCreateDate = "entityCreateDate"
    }
}

typealias SpyMessageRead = AyuSpyRecord<AyuSpyMessageReadTable>
typealias SpyMessageContentsRead = AyuSpyRecord<AyuSpyMessageContentsReadTable>
