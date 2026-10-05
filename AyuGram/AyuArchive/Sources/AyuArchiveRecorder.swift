import Foundation
import Postbox
import AyuDatabase
import AyuSettings

/// Captures messages that are about to be deleted.
///
/// Mirrors AyuGram's "Message Saving": the Android original is documented as
/// keeping its own Room database rather than Telegram's cache, so deleted
/// messages survive cache eviction and application updates. This is the iOS
/// counterpart, fed from the single deletion funnel in TelegramCore
/// (`_internal_deleteMessages`).
///
/// ## Threading
///
/// `recordDeletions` runs **inside a Postbox transaction**, which means the
/// postbox queue is locked and the `Transaction` is only valid for the duration
/// of the call. Messages are therefore read synchronously and converted to plain
/// values; the SQLite write happens afterwards on a private queue. Doing I/O on
/// the archive database while holding the postbox lock would serialise the two
/// databases for no reason.
///
/// ## What is captured
///
/// The scalar fields that map cleanly onto the Android columns, plus the message
/// text. The `messageSerialized` column stays NULL for now: `Message` and
/// `StoreMessage` are not `Codable`, and Postbox persists them through its own
/// `PostboxEncoder`, which needs a `SeedConfiguration` to decode attributes back.
/// Wiring that up is a separate, deliberate step — see AyuGram/docs/PORT-MAP.md.
public final class AyuArchiveRecorder {
    public static let shared = AyuArchiveRecorder()

    private let settings: AyuSettings
    private let lock = NSLock()
    private var accountId: Int64?
    private var store: AyuArchiveStore?

    /// Serialises archive writes; never runs while the postbox lock is held.
    private let writeQueue = DispatchQueue(label: "ayugram.archive.write", qos: .utility)

    public init(settings: AyuSettings = .shared) {
        self.settings = settings
    }

    /// Registers the account this process archives for.
    ///
    /// Called once from `Account.init`, because `Postbox.Transaction` does not
    /// expose the account peer id and the deletion funnel has no account
    /// parameter. Each account gets its own archive file, mirroring Android's
    /// per-account `ayu-data*` databases.
    public func connect(accountId: Int64) {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.accountId != accountId else {
            return
        }
        self.accountId = accountId
        self.store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
    }

    /// The account currently being archived for, if any.
    public var connectedAccountId: Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.accountId
    }

    /// Snapshots `ids` before Postbox removes them.
    ///
    /// Must be called from inside the transaction that performs the deletion —
    /// that is the only point where the message contents are still readable.
    public func recordDeletions(transaction: Transaction, ids: [MessageId]) {
        guard self.settings.saveDeletedMessages, !ids.isEmpty else {
            return
        }

        self.lock.lock()
        let currentAccountId = self.accountId
        let currentStore = self.store
        self.lock.unlock()

        guard let accountId = currentAccountId, let store = currentStore else {
            return
        }

        let createdAt = Int64(Date().timeIntervalSince1970 * 1000.0)
        var records: [DeletedMessage] = []
        records.reserveCapacity(ids.count)

        for id in ids {
            guard let message = transaction.getMessage(id) else {
                continue
            }
            records.append(AyuArchiveRecorder.snapshot(
                AyuDeletedMessageTable.self,
                message: message,
                id: id,
                accountId: accountId,
                createdAt: createdAt
            ))
        }

        guard !records.isEmpty else {
            return
        }

        self.writeQueue.async {
            // Best effort: a failure to archive must never surface as a failure
            // to delete, which the user did ask for.
            for record in records {
                do {
                    try store.insert(record)
                } catch {
                    assertionFailure("AyuGram archive insert failed: \(error)")
                }
            }
        }
    }

    /// Snapshots the revision that an edit is about to replace.
    ///
    /// Must be called inside the same Postbox transaction that applies the edit:
    /// at that point `transaction.getMessage` still returns the *previous*
    /// revision, which is the whole point of the feature.
    ///
    /// Every edit operation appends a row. No deduplication is attempted, because
    /// the obvious key — the message date — is identical for every revision of one
    /// message, so using it would discard all but the first. If Telegram replays
    /// an edit update, the archive gains a duplicate revision, which is cosmetic;
    /// losing revisions would not be.
    public func recordEdit(transaction: Transaction, id: MessageId) {
        guard self.settings.saveEditedMessages else {
            return
        }

        self.lock.lock()
        let currentAccountId = self.accountId
        let currentStore = self.store
        self.lock.unlock()

        guard let accountId = currentAccountId, let store = currentStore else {
            return
        }
        guard let message = transaction.getMessage(id) else {
            return
        }

        let record = AyuArchiveRecorder.snapshot(
            AyuEditedMessageTable.self,
            message: message,
            id: id,
            accountId: accountId,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000.0)
        )

        self.writeQueue.async {
            do {
                try store.insert(record)
            } catch {
                assertionFailure("AyuGram edited-revision insert failed: \(error)")
            }
        }
    }

    /// Converts a live `Message` into an archive row for a given table.
    ///
    /// Generic over the table kind, because deleted messages and edited revisions
    /// share one record type but are stored in two tables. Only fields whose
    /// Postbox API is stable are mapped; the rest belong to the deferred
    /// `messageSerialized` payload and are called out in the port map.
    static func snapshot<Table: AyuTableKind>(
        _ table: Table.Type,
        message: Message,
        id: MessageId,
        accountId: Int64,
        createdAt: Int64
    ) -> AyuMessageRecord<Table> {
        let forwardInfo = message.forwardInfo

        return AyuMessageRecord<Table>(
            userId: accountId,
            // `toInt64()` keeps channels negative, which is what the Android
            // queries and indexes expect.
            dialogId: id.peerId.toInt64(),
            peerId: id.peerId.toInt64(),
            fromId: message.author?.id.toInt64() ?? 0,
            topicId: message.threadId ?? 0,
            messageId: id.id,
            date: message.timestamp,
            flags: message.flags.rawValue,
            fwdFlags: forwardInfo?.flags.rawValue ?? 0,
            fwdFromId: forwardInfo?.authorId?.toInt64() ?? 0,
            fwdName: forwardInfo?.authorSignature,
            fwdDate: forwardInfo?.date ?? 0,
            entityCreateDate: createdAt,
            text: message.text
        )
    }
}
