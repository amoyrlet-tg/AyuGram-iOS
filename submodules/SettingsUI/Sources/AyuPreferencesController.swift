import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private let ayuGhostOptions: [(String, WritableKeyPath<AyuPreferences, Bool>)] = [
    ("Read messages", \.dontReadMessages),
    ("Read stories", \.dontReadStories),
    ("Don’t send online", \.dontSendOnline),
    ("Don’t send typing", \.dontSendActivity),
    ("Go offline automatically", \.autoOffline)
]

private struct AyuPreferenceEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let value: Bool?
    let theme: PresentationTheme
    let keyPath: WritableKeyPath<AyuPreferences, Bool>?
    var ghostPreferences: AyuPreferences? = nil
    var expanded = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.title == rhs.title && lhs.value == rhs.value && lhs.theme === rhs.theme && lhs.ghostPreferences == rhs.ghostPreferences && lhs.expanded == rhs.expanded
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.section != rhs.section { return lhs.section < rhs.section }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuPreferenceArguments
        if let preferences = self.ghostPreferences {
            let subItems = ayuGhostOptions.enumerated().map { index, option in
                let protected = preferences.ghostMode || preferences[keyPath: option.1]
                return ItemListExpandableSwitchItem.SubItem(id: index, title: option.0, isSelected: index < 2 ? !protected : protected, isEnabled: true)
            }
            return ItemListExpandableSwitchItem(presentationData: presentationData, title: self.title, value: preferences.ghostModeActive, isExpanded: self.expanded, subItems: subItems, sectionId: self.section, style: .blocks, updated: { enabled in
                if !arguments.store.update({ $0.setGhostModeEnabled(enabled) }) { arguments.failed() }
            }, selectAction: arguments.toggleGhost, subAction: { item in
                guard let index = item.id.base as? Int else { return }
                if !arguments.store.update({ value in
                    value.setGhostOption(ayuGhostOptions[index].1, enabled: index < 2 ? item.isSelected : !item.isSelected)
                }) { arguments.failed() }
            })
        }
        if let value = self.value, let keyPath = self.keyPath {
            return ItemListSwitchItem(presentationData: presentationData, title: self.title, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                if !arguments.store.update({ $0[keyPath: keyPath] = value }) {
                    arguments.failed()
                }
            })
        }
        if self.stableId == 10 || self.stableId == 13 || self.stableId == 14 {
            return ItemListActionItem(presentationData: presentationData, title: self.title, kind: self.stableId == 13 || self.stableId == 14 ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if self.stableId == 13 || self.stableId == 14 { arguments.clear() } else { arguments.delay() }
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
    var toggleGhost: () -> Void = {}
    init(store: AyuPreferencesStore, clear: @escaping () -> Void, delay: @escaping () -> Void, failed: @escaping () -> Void) {
        self.store = store
        self.clear = clear
        self.delay = delay
        self.failed = failed
    }
}

public func ayuPreferencesController(context: AccountContext) -> ViewController {
    let store = context.account.network.ayuPreferences
    var isGhostExpanded = true
    let ghostExpanded = ValuePromise<Bool>(true, ignoreRepeated: true)
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
    arguments.toggleGhost = {
        isGhostExpanded.toggle()
        ghostExpanded.set(isGhostExpanded)
    }
    let signal = combineLatest(context.sharedContext.presentationData, store.signal, status.get(), ghostExpanded.get())
    |> deliverOnMainQueue
    |> map { presentationData, preferences, status, expanded -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let rows: [(Int32, Int32, String, WritableKeyPath<AyuPreferences, Bool>)] = [
            (0, 0, "Ghost Mode · \(ayuGhostOptions.filter { preferences.ghostMode || preferences[keyPath: $0.1] }.count)/5", \.ghostMode),
            (7, 2, "Streamer Mode", \.streamerMode),
            (8, 2, "Hide names", \.hideNames),
            (9, 2, "Hide usernames", \.hideUsernames),
            (15, 2, "Hide phone numbers", \.hidePhoneNumbers),
            (16, 3, "Save deleted messages", \.saveDeletedMessages),
            (17, 3, "Save message edit history", \.saveEditHistory),
            (18, 3, "Automatically archive media", \.archiveMedia),
            (19, 4, "Show seconds in timestamps", \.showTimestampSeconds),
            (20, 5, "Auto-delete my messages", \.autoDeleteMessages),
            (21, 6, "Show numeric ID", \.showNumericId),
            (22, 6, "Show datacenter", \.showDcId)
        ]
        var entries = rows.map { id, section, title, keyPath in
            var entry = AyuPreferenceEntry(stableId: id, section: section, title: title, value: preferences[keyPath: keyPath], theme: presentationData.theme, keyPath: keyPath)
            if id == 0 {
                entry.ghostPreferences = preferences
                entry.expanded = expanded
            }
            return entry
        }
        entries.append(AyuPreferenceEntry(stableId: -1, section: 0, title: "Ghost essentials", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 6, section: 0, title: "Read messages / stories: on = mark as read; off = keep unread locally and on Telegram. Ghost Mode turns reading off and enables the other three protections.", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 10, section: 5, title: "Delete after: \(preferences.autoDeleteDelay) seconds · Tap to change", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 13, section: 7, title: "Clear AyuGram archive", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 14, section: 7, title: "Clear archived media", value: nil, theme: presentationData.theme, keyPath: nil))
        entries.append(AyuPreferenceEntry(stableId: 23, section: 7, title: status + " History is kept separately from Telegram cache.", value: nil, theme: presentationData.theme, keyPath: nil))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries.sorted(), style: .blocks, animateChanges: false), arguments))
    }
    return ItemListController(context: context, state: signal)
}
