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
import LegacyMediaPickerUI
import AyuDatabase

private enum AyuImportSection: Int32 {
    case info
    case action
}

private enum AyuImportEntry: ItemListNodeEntry {
    case notice(text: String)
    case status(text: String)
    case choose

    var section: ItemListSectionId {
        switch self {
        case .notice, .status: return AyuImportSection.info.rawValue
        case .choose: return AyuImportSection.action.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .notice: return 1
        case .status: return 2
        case .choose: return 3
        }
    }

    static func == (lhs: AyuImportEntry, rhs: AyuImportEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.notice(a), .notice(b)), let (.status(a), .status(b)):
            return a == b
        case (.choose, .choose):
            return true
        default:
            return false
        }
    }

    static func < (lhs: AyuImportEntry, rhs: AyuImportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuImportArguments
        switch self {
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section)
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .choose:
            return ItemListPeerActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: "Choose Archive File…",
                sectionId: self.section,
                height: .generic,
                action: {
                    arguments.chooseFile()
                }
            )
        }
    }
}

private final class AyuImportArguments {
    let chooseFile: () -> Void
    init(chooseFile: @escaping () -> Void) {
        self.chooseFile = chooseFile
    }
}

/// Imports the `ayu-data*` sqlite file exported by AyuGram for Android into the
/// per-account archive path. Opening the database afterwards runs the existing
/// Room-v32 migration chain (`AyuAndroidImporter.upgrade`).
public func ayuArchiveImportController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let statusPromise = Promise<String>(AyuDatabase.path(accountId: accountId))

    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuImportArguments(chooseFile: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let picker = legacyICloudFilePicker(
            theme: presentationData.theme,
            mode: .import,
            hasMultiselection: false,
            documentTypes: ["public.item"],
            completion: { urls in
                guard let url = urls.first else {
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    var message: String
                    do {
                        let data = try Data(contentsOf: url)
                        try data.write(to: URL(fileURLWithPath: AyuDatabase.path(accountId: accountId)), options: .atomic)
                        _ = AyuDatabase(accountId: accountId)
                        message = "Archive imported. Restart the app to finish attaching the database."
                    } catch {
                        message = "Import failed: \(error.localizedDescription)"
                    }
                    DispatchQueue.main.async {
                        statusPromise.set(.single(message))
                    }
                }
            }
        )
        presentControllerImpl?(picker)
    })

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> =
        combineLatest(context.sharedContext.presentationData, statusPromise.get())
        |> map { presentationData, status -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemPresentationData = ItemListPresentationData(presentationData)
            let entries: [AyuImportEntry] = [
                .notice(text: "Select an AyuGram Android archive (ayu-data*.sqlite). It replaces this account's current archive. The existing migration upgrades the Android schema automatically."),
                .status(text: status),
                .choose
            ]
            let controllerState = ItemListControllerState(
                presentationData: itemPresentationData,
                title: .text("Import Archive"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let listState = ItemListNodeState(presentationData: itemPresentationData, entries: entries, style: .blocks, animateChanges: false)
            return (controllerState, (listState, arguments))
        }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
