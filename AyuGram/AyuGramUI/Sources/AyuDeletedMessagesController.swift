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

private enum AyuDeletedSection: Int32 {
    case controls
    case messages
}

private struct AyuDeletedMessageRow: Equatable {
    let text: String
    let date: String
    let dialogId: Int64
    let messageId: Int32
}

private enum AyuDeletedEntry: ItemListNodeEntry {
    case search(text: String)
    case dialogFilter(text: String)
    case refresh
    case notice
    case message(index: Int, row: AyuDeletedMessageRow)

    var section: ItemListSectionId {
        switch self {
        case .search, .dialogFilter, .refresh, .notice:
            return AyuDeletedSection.controls.rawValue
        case .message:
            return AyuDeletedSection.messages.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .search: return 1
        case .dialogFilter: return 2
        case .refresh: return 3
        case .notice: return 4
        case let .message(index, _): return 100 + index
        }
    }

    static func == (lhs: AyuDeletedEntry, rhs: AyuDeletedEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.search(a), .search(b)):
            return a == b
        case let (.dialogFilter(a), .dialogFilter(b)):
            return a == b
        case (.refresh, .refresh), (.notice, .notice):
            return true
        case let (.message(ai, ar), .message(bi, br)):
            return ai == bi && ar == br
        default:
            return false
        }
    }

    static func < (lhs: AyuDeletedEntry, rhs: AyuDeletedEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuDeletedArguments
        switch self {
        case let .search(text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(),
                text: text,
                placeholder: "Search archived messages",
                returnKeyType: .search,
                spacing: 3.0,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { value in
                    arguments.updateSearch(value)
                },
                action: {},
                dismissKeyboardOnEnter: true
            )
        case let .dialogFilter(text):
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
                textUpdated: { value in
                    arguments.updateDialogFilter(value)
                },
                action: {},
                dismissKeyboardOnEnter: true
            )
        case .refresh:
            return ItemListPeerActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: "Refresh",
                sectionId: self.section,
                height: .generic,
                action: {
                    arguments.reload()
                }
            )
        case .notice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .markdown("Messages deleted in Telegram are kept in AyuGram's own database. Tap a message to see who read it."),
                sectionId: self.section
            )
        case let .message(_, row):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: row.text,
                label: row.date,
                sectionId: self.section,
                style: .blocks
            ) {
                arguments.openReaders(row.dialogId, row.messageId)
            }
        }
    }
}

private final class AyuDeletedArguments {
    let updateSearch: (String) -> Void
    let updateDialogFilter: (String) -> Void
    let reload: () -> Void
    let openReaders: (Int64, Int32) -> Void

    init(
        updateSearch: @escaping (String) -> Void,
        updateDialogFilter: @escaping (String) -> Void,
        reload: @escaping () -> Void,
        openReaders: @escaping (Int64, Int32) -> Void
    ) {
        self.updateSearch = updateSearch
        self.updateDialogFilter = updateDialogFilter
        self.reload = reload
        self.openReaders = openReaders
    }
}

private struct AyuDeletedState: Equatable {
    var searchQuery: String = ""
    var dialogFilter: String = ""
}

/// The "View Deleted" screen that the Android original has and the iOS port lacked.
public func ayuDeletedMessagesController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let initialState = AyuDeletedState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((AyuDeletedState) -> AyuDeletedState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let recordsPromise = Promise<[DeletedMessage]>()
    let reload = { (dialogId: Int64?) in
        recordsPromise.set(ayuLoadRecords {
            let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
            if let dialogId = dialogId {
                return try store.deletedMessages(accountId: accountId, dialogId: dialogId, limit: 500)
            }
            return try store.fetch(
                DeletedMessage.self,
                "\(DeletedMessage.sqlSelectAll) WHERE `userId` = ? ORDER BY `entityCreateDate` DESC LIMIT 500",
                [.integer(accountId)]
            )
        })
    }
    reload(nil)

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuDeletedArguments(
        updateSearch: { query in
            updateState { state in
                var updated = state
                updated.searchQuery = query
                return updated
            }
        },
        updateDialogFilter: { text in
            updateState { state in
                var updated = state
                updated.dialogFilter = text
                return updated
            }
            reload(ayuParseDialogId(text))
        },
        reload: {
            reload(ayuParseDialogId(stateValue.with { $0.dialogFilter }))
        },
        openReaders: { dialogId, messageId in
            pushControllerImpl?(ayuWhoReadController(context: context, dialogId: dialogId, messageId: messageId))
        }
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> =
        combineLatest(context.sharedContext.presentationData, statePromise.get(), recordsPromise.get())
        |> map { presentationData, state, records -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemPresentationData = ItemListPresentationData(presentationData)
            var entries: [AyuDeletedEntry] = [
                .search(text: state.searchQuery),
                .dialogFilter(text: state.dialogFilter),
                .refresh,
                .notice
            ]

            let query = state.searchQuery.lowercased()
            let matching = records.filter { record in
                if query.isEmpty {
                    return true
                }
                return (record.text ?? "").lowercased().contains(query)
                    || String(record.messageId).contains(query)
                    || String(record.dialogId).contains(query)
            }
            for (index, record) in matching.enumerated() {
                let row = AyuDeletedMessageRow(
                    text: ayuSnippet(record.text),
                    date: ayuFormatMillis(record.entityCreateDate),
                    dialogId: record.dialogId,
                    messageId: record.messageId
                )
                entries.append(.message(index: index, row: row))
            }

            let controllerState = ItemListControllerState(
                presentationData: itemPresentationData,
                title: .text("Deleted Messages"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let listState = ItemListNodeState(
                presentationData: itemPresentationData,
                entries: entries,
                style: .blocks,
                emptyStateItem: ItemListTextEmptyStateItem(text: "No deleted messages found."),
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
