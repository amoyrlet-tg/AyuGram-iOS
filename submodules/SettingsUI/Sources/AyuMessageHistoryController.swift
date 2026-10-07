import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct AyuHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    var section: ItemListSectionId { self.stableId }
    let text: String
    let theme: PresentationTheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.text == rhs.text && lhs.theme === rhs.theme
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        return ItemListTextItem(presentationData: presentationData, text: .plain(self.text), sectionId: self.section)
    }
}

public func ayuMessageHistoryController(context: AccountContext, message: EngineRawMessage) -> ViewController {
    let archive = AyuMessageArchive.get(mediaBox: context.account.postbox.mediaBox)
    let revisions = archive.revisions(message.id)
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        var entries: [AyuHistoryEntry] = []
        let deleted = message.attributes.contains(where: { $0 is AyuDeletedMessageAttribute })
        entries.append(AyuHistoryEntry(stableId: 0, text: (deleted ? "Deleted message" : "Current message") + "\n\n" + (message.text.isEmpty ? "[Media message]" : message.text), theme: presentationData.theme))
        for (index, revision) in revisions.reversed().enumerated() {
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(revision.capturedAt)))
            entries.append(AyuHistoryEntry(stableId: Int32(index + 1), text: (revision.deleted ? "Deleted · " : "Before edit · ") + date + "\n\n" + (revision.text.isEmpty ? "[Media message]" : revision.text), theme: presentationData.theme))
        }
        if revisions.isEmpty {
            entries.append(AyuHistoryEntry(stableId: 1, text: "No earlier versions saved on this device.", theme: presentationData.theme))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), ()))
    }
    return ItemListController(context: context, state: signal)
}
