import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct AyuPreferenceEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let value: Bool?
    let theme: PresentationTheme
    let keyPath: WritableKeyPath<AyuPreferences, Bool>?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.title == rhs.title && lhs.value == rhs.value && lhs.theme === rhs.theme
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuPreferenceArguments
        if let value = self.value, let keyPath = self.keyPath {
            return ItemListSwitchItem(presentationData: presentationData, title: self.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                if !arguments.store.update({ $0[keyPath: keyPath] = value }) {
                    arguments.failed()
                }
            })
        }
        if self.stableId == 10 || self.stableId == 13 {
            return ItemListActionItem(presentationData: presentationData, title: self.title, kind: self.stableId == 13 ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if self.stableId == 13 { arguments.clear() } else { arguments.delay() }
            })
        }
        return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
    }
}

private final class AyuPreferenceArguments {
    let store: AyuPreferencesStore
    let clear: () -> Void
    let delay: () -> Void
    let failed: () -> Void
    init(store: AyuPreferencesStore, clear: @escaping () -> Void, delay: @escaping () -> Void, failed: @escaping () -> Void) {
        self.store = store
        self.clear = clear
        self.delay = delay
        self.failed = failed
    }
}

public func ayuPreferencesController(context: AccountContext) -> ViewController {
    let store = context.account.network.ayuPreferences
    let status = ValuePromise<String>("History is stored on this device, separately for each account.", ignoreRepeated: true)
    let arguments = AyuPreferenceArguments(store: store, clear: {
        status.set("Clearing AyuGram cache…")
        let _ = (AyuMessageArchive.get(mediaBox: context.account.postbox.mediaBox).clear(postbox: context.account.postbox)
        |> deliverOnMainQueue).startStandalone(next: { success in
            status.set(success ? "AyuGram cache cleared." : "Could not clear the complete cache. Please try again.")
        })
    }, delay: {
        let values: [Int32] = [30, 60, 180, 300, 600, 3600, 86400]
        if !store.update({ value in
            let index = values.firstIndex(of: value.autoDeleteDelay) ?? 1
            value.autoDeleteDelay = values[(index + 1) % values.count]
        }) {
            status.set("Could not save preferences. Please try again.")
        }
    }, failed: {
        status.set("Could not save preferences. Please try again.")
    })
    let signal = combineLatest(context.sharedContext.presentationData, store.signal, status.get())
    |> deliverOnMainQueue
    |> map { presentationData, preferences, status -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let rows: [(Int32, Int32, String, WritableKeyPath<AyuPreferences, Bool>)] = [
            (0, 0, "Ghost Mode", \.ghostMode),
            (1, 0, "Don’t read messages", \.dontReadMessages),
            (2, 0, "Don’t read stories", \.dontReadStories),
            (3, 0, "Don’t send typing / recording / uploading status", \.dontSendActivity),
            (4, 0, "Don’t send online status", \.dontSendOnline),
            (5, 0, "Auto go offline", \.autoOffline),
            (7, 1, "Save deleted messages", \.saveDeletedMessages),
            (8, 1, "Save message edit history", \.saveEditHistory),
            (9, 2, "Auto-delete my messages", \.autoDeleteMessages),
            (11, 3, "Show numeric ID (Bot API)", \.showNumericId),
            (12, 3, "Show known DC ID", \.showDcId)
        ]
        var entries = rows.map { id, section, title, keyPath in
            AyuPreferenceEntry(stableId: id, section: section, title: title, value: preferences[keyPath: keyPath], theme: presentationData.theme, keyPath: keyPath)
        }
        entries.append(AyuPreferenceEntry(stableId: 6, section: 0, title: "Ghost Mode overrides the read, activity and online switches. Active actions may expose presence briefly; AyuGram sends offline when they finish.", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 10, section: 2, title: "Delete after: \(preferences.autoDeleteDelay) seconds · Tap to change", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 13, section: 4, title: "Clear AyuGram cache", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 14, section: 4, title: status + " Only messages received by this device can be saved. Auto-delete runs while enabled and resumes when the app can connect to Telegram.", value: nil, theme: presentationData.theme, keyPath: nil))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram Preferences"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries.sorted(), style: .blocks, animateChanges: false), arguments))
    }
    return ItemListController(context: context, state: signal)
}
