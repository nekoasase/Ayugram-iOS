// MARK: AyuGram
import Foundation
import AyuFilters
import AyuSettings
import AyuDatabase

/// A point-in-time copy of the filter tables, so the render path never touches SQLite.
public struct AyuFilterSnapshot {
    public let filters: [RegexFilter]
    public let exclusions: [RegexFilterGlobalExclusion]

    public init(filters: [RegexFilter], exclusions: [RegexFilterGlobalExclusion]) {
        self.filters = filters
        self.exclusions = exclusions
    }
}

/// Maps stored `RegexFilter` rows onto `AyuFilterRule` values and evaluates them.
///
/// The chat render path calls `isFiltered(_:dialogId:accountId:)` once per message,
/// so the tables are read on a background queue and cached. A database failure
/// keeps the previous snapshot — a transient sqlite error must never make the
/// whole chat disappear.
public final class AyuFilterBridge {
    public static let shared = AyuFilterBridge()

    private let engine = AyuFilterEngine()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ayugram.filter.bridge", qos: .utility)
    private var loadedAccountId: Int64?
    private var snapshot: AyuFilterSnapshot?

    private init() {
    }

    /// Reloads the filter tables from the given account's database.
    public func refresh(accountId: Int64) {
        self.queue.async {
            do {
                let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
                let filters = try store.allFilters()
                let exclusions = try store.fetch(
                    RegexFilterGlobalExclusion.self,
                    RegexFilterGlobalExclusion.sqlSelectAll
                )
                let newSnapshot = AyuFilterSnapshot(filters: filters, exclusions: exclusions)
                self.lock.lock()
                self.loadedAccountId = accountId
                self.snapshot = newSnapshot
                self.lock.unlock()
            } catch {
                // Keep the last good snapshot.
            }
        }
    }

    /// Applies the same scope rules as `RegexFilter.applicableQuery`:
    /// enabled rules, dialog-scoped to this dialog, plus global rules unless
    /// explicitly excluded from it.
    public func rules(dialogId: Int64, accountId: Int64) -> [AyuFilterRule] {
        self.lock.lock()
        let current = self.snapshot
        let loaded = self.loadedAccountId
        self.lock.unlock()

        if current == nil || loaded != accountId {
            self.refresh(accountId: accountId)
            return []
        }
        guard let snapshot = current else {
            return []
        }

        let excludedIds = Set(
            snapshot.exclusions
                .filter { $0.dialogId == dialogId }
                .compactMap { $0.filterId }
        )

        return snapshot.filters.compactMap { filter in
            guard filter.enabled else {
                return nil
            }
            if let scopedDialogId = filter.dialogId {
                guard scopedDialogId == dialogId else {
                    return nil
                }
            } else if excludedIds.contains(filter.id) {
                return nil
            }
            return AyuFilterRule(
                pattern: filter.text ?? "",
                isCaseInsensitive: filter.caseInsensitive,
                isReversed: filter.reversed
            )
        }
    }

    /// Whether a message with this text should be hidden from the given dialog.
    public func isFiltered(_ text: String, dialogId: Int64, accountId: Int64) -> Bool {
        guard AyuSettings.shared.regexFiltersEnabled else {
            return false
        }
        let applicableRules = self.rules(dialogId: dialogId, accountId: accountId)
        guard !applicableRules.isEmpty else {
            return false
        }
        return self.engine.isFiltered(text, by: applicableRules)
    }
}
