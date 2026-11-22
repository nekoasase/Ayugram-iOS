// MARK: AyuGram
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AyuDatabase

private enum AyuReadersSection: Int32 {
    case info
    case readers
    case contentReaders
}

private struct AyuReaderRow: Equatable {
    let readerId: Int64
    let date: String
}

private enum AyuReadersEntry: ItemListNodeEntry {
    case info(text: String)
    case section(section: AyuReadersSection, title: String)
    case empty(section: AyuReadersSection, text: String)
    case reader(section: AyuReadersSection, index: Int, row: AyuReaderRow)

    var section: ItemListSectionId {
        switch self {
        case let .section(section, _), let .empty(section, _), let .reader(section, _, _):
            return section.rawValue
        case .info:
            return AyuReadersSection.info.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .info: return 0
        case let .section(section, _): return 10 + Int(section.rawValue)
        case let .empty(section, _): return 100 + Int(section.rawValue)
        case let .reader(section, index, _): return 1000 + Int(section.rawValue) * 1000 + index
        }
    }

    static func == (lhs: AyuReadersEntry, rhs: AyuReadersEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.info(a), .info(b)):
            return a == b
        case let (.section(a, at), .section(b, bt)):
            return a == b && at == bt
        case let (.empty(a, at), .empty(b, bt)):
            return a == b && at == bt
        case let (.reader(aSection, ai, ar), .reader(bSection, bi, br)):
            return aSection == bSection && ai == bi && ar == br
        default:
            return false
        }
    }

    static func < (lhs: AyuReadersEntry, rhs: AyuReadersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .info(text):
            return ItemListTextItem(
                presentationData: presentationData,
                text: .markdown(text),
                sectionId: self.section
            )
        case let .section(_, title):
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: title,
                sectionId: self.section
            )
        case let .empty(_, text):
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain(text),
                sectionId: self.section
            )
        case let .reader(_, _, row):
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("User \(row.readerId) — \(row.date)"),
                sectionId: self.section
            )
        }
    }
}

private struct AyuReadersData: Equatable {
    var readers: [AyuReaderRow] = []
    var contentReaders: [AyuReaderRow] = []
}

/// Shows who read a given message and when. Read dates are recorded by the
/// anti-delete layer; Telegram itself only exposes reader ids for outgoing
/// messages in private chats.
public func ayuWhoReadController(context: AccountContext, dialogId: Int64, messageId: Int32) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let dataPromise = Promise<AyuReadersData>(AyuReadersData())

    dataPromise.set(Signal { subscriber in
        DispatchQueue.global(qos: .utility).async {
            var data = AyuReadersData()
            do {
                let store = AyuArchiveStore(database: AyuDatabase(accountId: accountId))
                let readers = try store.readersOfMessage(dialogId: dialogId, messageId: messageId)
                data.readers = readers.map {
                    AyuReaderRow(readerId: $0.userId, date: ayuFormatMillis($0.entityCreateDate))
                }
                let contentIds = try store.contentReaderIds(dialogId: dialogId, messageId: messageId)
                data.contentReaders = contentIds.map {
                    AyuReaderRow(readerId: $0, date: "")
                }
            } catch {
                // An empty screen is preferable to a crash.
            }
            DispatchQueue.main.async {
                subscriber.putNext(data)
                subscriber.putCompletion()
            }
        }
        return EmptyDisposable
    })

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> =
        combineLatest(context.sharedContext.presentationData, dataPromise.get())
        |> map { presentationData, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemPresentationData = ItemListPresentationData(presentationData)
            var entries: [AyuReadersEntry] = [
                .info(text: "Message \(messageId) in chat \(dialogId). Telegram does not report the reader for content reads in groups, so those entries have no name or date.")
            ]

            entries.append(.section(section: .readers, title: "Read"))
            if data.readers.isEmpty {
                entries.append(.empty(section: .readers, text: "No read records."))
            } else {
                for (index, row) in data.readers.enumerated() {
                    entries.append(.reader(section: .readers, index: index, row: row))
                }
            }

            entries.append(.section(section: .contentReaders, title: "Contents read"))
            if data.contentReaders.isEmpty {
                entries.append(.empty(section: .contentReaders, text: "No content-read records."))
            } else {
                for (index, row) in data.contentReaders.enumerated() {
                    entries.append(.reader(section: .contentReaders, index: index, row: row))
                }
            }

            let controllerState = ItemListControllerState(
                presentationData: itemPresentationData,
                title: .text("Who Read"),
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
            return (controllerState, (listState, ()))
        }

    return ItemListController(context: context, state: signal)
}
