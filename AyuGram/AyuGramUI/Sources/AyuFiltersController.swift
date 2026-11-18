// MARK: AyuGram
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerActionItem
import PresentationDataUtils
import AccountContext
import AyuDatabase
import AyuSettings
import AyuFilterBridge

private enum AyuFiltersSection: Int32 {
    case settings
    case filters
}

private struct AyuFilterRow: Equatable {
    let id: Data
    let pattern: String
    let scope: String
    let flags: String
    let enabled: Bool
}

private enum AyuFiltersEntry: ItemListNodeEntry {
    case enabled(value: Bool)
    case chatList(value: Bool)
    case notice
    case add
    case filter(index: Int, row: AyuFilterRow)

    var section: ItemListSectionId {
        switch self {
        case .enabled, .chatList, .notice, .add:
            return AyuFiltersSection.settings.rawValue
        case .filter:
            return AyuFiltersSection.filters.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .enabled: return 1
        case .chatList: return 2
        case .notice: return 3
        case .add: return 4
        case let .filter(index, _): return 100 + index
        }
    }

    static func == (lhs: AyuFiltersEntry, rhs: AyuFiltersEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.enabled(a), .enabled(b)), let (.chatList(a), .chatList(b)):
            return a == b
        case (.notice, .notice), (.add, .add):
            return true
        case let (.filter(ai, ar), .filter(bi, br)):
            return ai == bi && ar == br
        default:
            return false
        }
    }

    static func < (lhs: AyuFiltersEntry, rhs: AyuFiltersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuFiltersArguments
        switch self {
        case let .enabled(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Enable Regex Filters",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setEnabled(newValue)
                }
            )
        case let .chatList(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Apply to Chat List",
                value: value,
                enabled: AyuSettings.shared.regexFiltersEnabled,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setChatList(newValue)
                }
            )
        case .notice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .markdown("A rule hides a message when its text matches the pattern. An inverted rule hides everything that does NOT match (allow-list). Invalid patterns are ignored."),
                sectionId: self.section
            )
        case .add:
            return ItemListPeerActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: "Add Filter",
                sectionId: self.section,
                height: .generic,
                action: {
                    arguments.openFilter(nil)
                }
            )
        case let .filter(_, row):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: row.pattern,
                enabled: row.enabled,
                label: row.scope,
                additionalDetailLabel: row.flags,
                sectionId: self.section,
                style: .blocks
            ) {
                arguments.openFilter(row.id)
            }
        }
    }
}

private final class AyuFiltersArguments {
    let setEnabled: (Bool) -> Void
    let setChatList: (Bool) -> Void
    let openFilter: (Data?) -> Void

    init(setEnabled: @escaping (Bool) -> Void, setChatList: @escaping (Bool) -> Void, openFilter: @escaping (Data?) -> Void) {
        self.setEnabled = setEnabled
        self.setChatList = setChatList
        self.openFilter = openFilter
    }
}

/// Regex-filter management: the engine and schema existed, but there was no screen
/// to create, edit or delete rules.
public func ayuFiltersController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let filtersPromise = Promise<[RegexFilter]>()
    let reload = {
        filtersPromise.set(ayuLoadRecords {
            let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
            return try store.allFilters()
        })
    }
    reload()

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuFiltersArguments(
        setEnabled: { value in
            AyuSettings.shared.regexFiltersEnabled = value
            AyuFilterBridge.shared.refresh(accountId: accountId)
        },
        setChatList: { value in
            AyuSettings.shared.regexFiltersApplyToChatList = value
        },
        openFilter: { id in
            pushControllerImpl?(ayuFilterEditController(context: context, accountId: accountId, filterId: id, reload: reload))
        }
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> =
        combineLatest(context.sharedContext.presentationData, filtersPromise.get())
        |> map { presentationData, filters -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemPresentationData = ItemListPresentationData(presentationData)
            var entries: [AyuFiltersEntry] = [
                .enabled(value: AyuSettings.shared.regexFiltersEnabled),
                .chatList(value: AyuSettings.shared.regexFiltersApplyToChatList),
                .notice,
                .add
            ]
            for (index, filter) in filters.enumerated() {
                let scope: String
                if let dialogId = filter.dialogId {
                    scope = "chat \(dialogId)"
                } else {
                    scope = "all chats"
                }
                var flags: [String] = []
                if filter.reversed { flags.append("inverted") }
                if filter.caseInsensitive { flags.append("ignore case") }
                let row = AyuFilterRow(
                    id: filter.id,
                    pattern: filter.text ?? "",
                    scope: scope,
                    flags: flags.joined(separator: ", "),
                    enabled: filter.enabled
                )
                entries.append(.filter(index: index, row: row))
            }

            let controllerState = ItemListControllerState(
                presentationData: itemPresentationData,
                title: .text("Regex Filters"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let listState = ItemListNodeState(
                presentationData: itemPresentationData,
                entries: entries,
                style: .blocks,
                animateChanges: false
            )
            return (controllerState, (listState, arguments))
        }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Edit screen

private enum AyuFilterEditSection: Int32 {
    case fields
    case options
    case actions
}

private struct AyuFilterEditState: Equatable {
    var pattern: String
    var dialogIdText: String
    var enabled: Bool
    var reversed: Bool
    var caseInsensitive: Bool
}

private enum AyuFilterEditEntry: ItemListNodeEntry {
    case pattern(text: String)
    case dialogId(text: String)
    case enabled(value: Bool)
    case reversed(value: Bool)
    case caseInsensitive(value: Bool)
    case notice
    case save
    case delete

    var section: ItemListSectionId {
        switch self {
        case .pattern, .dialogId: return AyuFilterEditSection.fields.rawValue
        case .enabled, .reversed, .caseInsensitive, .notice: return AyuFilterEditSection.options.rawValue
        case .save, .delete: return AyuFilterEditSection.actions.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .pattern: return 1
        case .dialogId: return 2
        case .enabled: return 3
        case .reversed: return 4
        case .caseInsensitive: return 5
        case .notice: return 6
        case .save: return 7
        case .delete: return 8
        }
    }

    static func == (lhs: AyuFilterEditEntry, rhs: AyuFilterEditEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.pattern(a), .pattern(b)), let (.dialogId(a), .dialogId(b)):
            return a == b
        case let (.enabled(a), .enabled(b)), let (.reversed(a), .reversed(b)), let (.caseInsensitive(a), .caseInsensitive(b)):
            return a == b
        case (.notice, .notice), (.save, .save), (.delete, .delete):
            return true
        default:
            return false
        }
    }

    static func < (lhs: AyuFilterEditEntry, rhs: AyuFilterEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuFilterEditArguments
        switch self {
        case let .pattern(text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(),
                text: text,
                placeholder: "Regular expression",
                returnKeyType: .done,
                spacing: 3.0,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { value in arguments.updatePattern(value) },
                action: {},
                dismissKeyboardOnEnter: true
            )
        case let .dialogId(text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "Chat ID"),
                text: text,
                placeholder: "0 = all chats",
                returnKeyType: .done,
                spacing: 3.0,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { value in arguments.updateDialogId(value) },
                action: {},
                dismissKeyboardOnEnter: true
            )
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Enabled", value: value, sectionId: self.section, style: .blocks, updated: { arguments.updateEnabled($0) })
        case let .reversed(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Inverted (allow-list)", value: value, sectionId: self.section, style: .blocks, updated: { arguments.updateReversed($0) })
        case let .caseInsensitive(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Case Insensitive", value: value, sectionId: self.section, style: .blocks, updated: { arguments.updateCaseInsensitive($0) })
        case .notice:
            return ItemListTextItem(presentationData: presentationData, text: .markdown("An empty or invalid pattern is ignored. A chat ID restricts the rule to one conversation."), sectionId: self.section)
        case .save:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Save", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.save() })
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Delete Filter", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.delete() })
        }
    }
}

private final class AyuFilterEditArguments {
    let updatePattern: (String) -> Void
    let updateDialogId: (String) -> Void
    let updateEnabled: (Bool) -> Void
    let updateReversed: (Bool) -> Void
    let updateCaseInsensitive: (Bool) -> Void
    let save: () -> Void
    let delete: () -> Void

    init(updatePattern: @escaping (String) -> Void, updateDialogId: @escaping (String) -> Void,
         updateEnabled: @escaping (Bool) -> Void, updateReversed: @escaping (Bool) -> Void,
         updateCaseInsensitive: @escaping (Bool) -> Void, save: @escaping () -> Void, delete: @escaping () -> Void) {
        self.updatePattern = updatePattern
        self.updateDialogId = updateDialogId
        self.updateEnabled = updateEnabled
        self.updateReversed = updateReversed
        self.updateCaseInsensitive = updateCaseInsensitive
        self.save = save
        self.delete = delete
    }
}

private func ayuFilterEditController(
    context: AccountContext,
    accountId: Int64,
    filterId: Data?,
    reload: @escaping () -> Void
) -> ViewController {
    let existingPromise = Promise<RegexFilter?>()
    if let filterId = filterId {
        existingPromise.set(Signal { subscriber in
            DispatchQueue.global(qos: .utility).async {
                let filter = try? AyuArchiveStore(database: AyuDatabase(accountId: accountId))
                    .fetch(RegexFilter.self, "\(RegexFilter.sqlSelectAll) WHERE `id` = ?", [.blob(filterId)])
                    .first
                DispatchQueue.main.async {
                    subscriber.putNext(filter)
                    subscriber.putCompletion()
                }
            }
            return EmptyDisposable
        })
    } else {
        existingPromise.set(.single(nil))
    }

    let initialState = AyuFilterEditState(pattern: "", dialogIdText: "0", enabled: true, reversed: false, caseInsensitive: true)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((AyuFilterEditState) -> AyuFilterEditState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var initialized = false
    let _ = (existingPromise.get() |> deliverOnMainQueue).start(next: { existing in
        if initialized { return }
        initialized = true
        if let existing = existing {
            updateState { _ in
                AyuFilterEditState(
                    pattern: existing.text ?? "",
                    dialogIdText: existing.dialogId.map { String($0) } ?? "0",
                    enabled: existing.enabled,
                    reversed: existing.reversed,
                    caseInsensitive: existing.caseInsensitive
                )
            }
        }
    })

    var dismissImpl: (() -> Void)?

    let arguments = AyuFilterEditArguments(
        updatePattern: { value in updateState { state in var s = state; s.pattern = value; return s } },
        updateDialogId: { value in updateState { state in var s = state; s.dialogIdText = value; return s } },
        updateEnabled: { value in updateState { state in var s = state; s.enabled = value; return s } },
        updateReversed: { value in updateState { state in var s = state; s.reversed = value; return s } },
        updateCaseInsensitive: { value in updateState { state in var s = state; s.caseInsensitive = value; return s } },
        save: {
            let state = stateValue.with { $0 }
            let dialogId = ayuParseDialogId(state.dialogIdText)
            let filter: RegexFilter
            if let filterId = filterId {
                filter = RegexFilter(id: filterId, text: state.pattern, enabled: state.enabled,
                                     reversed: state.reversed, caseInsensitive: state.caseInsensitive, dialogId: dialogId)
            } else {
                filter = RegexFilter.make(text: state.pattern, reversed: state.reversed,
                                          caseInsensitive: state.caseInsensitive, dialogId: dialogId)
            }
            DispatchQueue.global(qos: .utility).async {
                do {
                    let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
                    try store.saveFilter(filter)
                    AyuFilterBridge.shared.refresh(accountId: accountId)
                    reload()
                } catch {
                }
                DispatchQueue.main.async {
                    dismissImpl?()
                }
            }
        },
        delete: {
            guard let filterId = filterId else { return }
            DispatchQueue.global(qos: .utility).async {
                do {
                    let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
                    try store.deleteFilter(id: filterId)
                    AyuFilterBridge.shared.refresh(accountId: accountId)
                    reload()
                } catch {
                }
                DispatchQueue.main.async {
                    dismissImpl?()
                }
            }
        }
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> =
        combineLatest(context.sharedContext.presentationData, statePromise.get())
        |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemPresentationData = ItemListPresentationData(presentationData)
            var entries: [AyuFilterEditEntry] = [
                .pattern(text: state.pattern),
                .dialogId(text: state.dialogIdText),
                .enabled(value: state.enabled),
                .reversed(value: state.reversed),
                .caseInsensitive(value: state.caseInsensitive),
                .notice,
                .save
            ]
            if filterId != nil {
                entries.append(.delete)
            }
            let controllerState = ItemListControllerState(
                presentationData: itemPresentationData,
                title: .text(filterId == nil ? "New Filter" : "Edit Filter"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let listState = ItemListNodeState(presentationData: itemPresentationData, entries: entries, style: .blocks, animateChanges: false)
            return (controllerState, (listState, arguments))
        }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
