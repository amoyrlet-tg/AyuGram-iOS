import Foundation
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct AyuHistoryMoment: Hashable, Comparable {
    let timestamp: Int32
    let occurrence: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.occurrence < rhs.occurrence : lhs.timestamp < rhs.timestamp
    }
}

private struct AyuHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    var section: ItemListSectionId { 0 }
    let text: String
    let messages: [EngineRawMessage]
    let data: PresentationData

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.text == rhs.text && lhs.data === rhs.data
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let context = arguments as! AccountContext
        guard !self.messages.isEmpty else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.text), sectionId: self.section)
        }
        return context.sharedContext.makeChatMessagePreviewItem(
            context: context, messages: self.messages, theme: self.data.theme, strings: self.data.strings,
            wallpaper: self.data.chatWallpaper, fontSize: self.data.chatFontSize,
            chatBubbleCorners: self.data.chatBubbleCorners, dateTimeFormat: self.data.dateTimeFormat,
            nameOrder: self.data.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil,
            clickThroughMessage: nil, backgroundNode: nil, availableReactions: nil, accountPeer: nil,
            isCentered: false, isPreview: true, isStandalone: true, rank: nil, rankRole: nil
        )
    }
}

private func historyMessage(source: Message, revision: AyuMessageRevision?, id: Int32, groupingKey: Int64?) -> Message {
    var media = source.media
    var attributes = source.attributes
    if let revision {
        let decoder = PostboxDecoder(buffer: MemoryBuffer(data: revision.payload))
        media = decoder.decodeObjectArrayForKey("media").compactMap { $0 as? Media }
        attributes = decoder.decodeObjectArrayForKey("attributes").compactMap { $0 as? MessageAttribute }
    }
    return Message(
        stableId: UInt32(id), stableVersion: 0,
        id: MessageId(peerId: source.id.peerId, namespace: Namespaces.Message.Local, id: id),
        globallyUniqueId: nil, groupingKey: groupingKey, groupInfo: nil, threadId: nil,
        timestamp: revision?.timestamp ?? source.timestamp, flags: source.flags,
        tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
        author: revision?.senderId.flatMap { source.peers[PeerId($0)] } ?? source.author,
        text: revision?.text ?? source.text, attributes: attributes, media: media,
        peers: source.peers, associatedMessages: source.associatedMessages, associatedMessageIds: [],
        associatedMedia: source.associatedMedia, associatedThreadInfo: nil, associatedStories: source.associatedStories
    )
}

public func ayuMessageHistoryController(context: AccountContext, messages: [EngineRawMessage]) -> ViewController {
    let sources = messages.sorted { $0.index < $1.index }
    let archive = AyuMessageArchive.get(mediaBox: context.account.postbox.mediaBox)
    let histories = sources.map { source -> [(AyuHistoryMoment, AyuMessageRevision)] in
        var occurrences: [Int32: Int] = [:]
        return archive.revisions(source.id).map { revision in
            let occurrence = occurrences[revision.capturedAt, default: 0]
            occurrences[revision.capturedAt] = occurrence + 1
            return (AyuHistoryMoment(timestamp: revision.capturedAt, occurrence: occurrence), revision)
        }
    }
    let moments = Set(histories.flatMap { $0.map { $0.0 } }).sorted()
    let signal = context.sharedContext.presentationData |> deliverOnMainQueue
    |> map { data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        var entries: [AyuHistoryEntry] = []
        var nextId: Int32 = 1
        func append(_ text: String, messages: [Message] = []) {
            entries.append(AyuHistoryEntry(stableId: Int32(entries.count), text: text, messages: messages, data: data))
        }
        append("Local history · Saved versions on this device. Album items are displayed together.")
        for (frame, moment) in moments.enumerated() {
            let snapshot = sources.enumerated().map { index, source -> Message in
                let revisions = histories[index]
                let revision = revisions.last(where: { $0.0 <= moment })?.1 ?? revisions.first?.1
                defer { nextId += 1 }
                return historyMessage(source: source, revision: revision, id: nextId, groupingKey: sources.count > 1 ? Int64(frame + 1) : nil)
            }
            let deleted = histories.contains { $0.contains { $0.0 == moment && $0.1.deleted } }
            let label = deleted ? "Deleted" : (frame == 0 ? "Original saved version" : "Saved before edit")
            append(label + " · " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(moment.timestamp))))
            append("", messages: snapshot)
        }
        append(sources.contains { $0.attributes.contains { $0 is AyuDeletedMessageAttribute } } ? "Last saved version" : "Current version")
        append("", messages: sources.map { source in
            defer { nextId += 1 }
            return historyMessage(source: source, revision: nil, id: nextId, groupingKey: sources.count > 1 ? Int64(moments.count + 1) : nil)
        })
        if moments.isEmpty { append("No earlier versions saved on this device.") }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(sources.count > 1 ? "Album History" : "Message History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .plain, animateChanges: false), context))
    }
    return ItemListController(context: context, state: signal)
}
