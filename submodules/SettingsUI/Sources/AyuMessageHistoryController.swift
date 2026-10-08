import Foundation
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct AyuHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    var section: ItemListSectionId { 0 }
    let text: String
    let message: EngineRawMessage?
    let data: PresentationData

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.text == rhs.text && lhs.data === rhs.data
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let context = arguments as! AccountContext
        guard let message = self.message else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.text), sectionId: self.section)
        }
        return context.sharedContext.makeChatMessagePreviewItem(
            context: context, messages: [message], theme: self.data.theme, strings: self.data.strings,
            wallpaper: self.data.chatWallpaper, fontSize: self.data.chatFontSize,
            chatBubbleCorners: self.data.chatBubbleCorners, dateTimeFormat: self.data.dateTimeFormat,
            nameOrder: self.data.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil,
            clickThroughMessage: nil, backgroundNode: nil, availableReactions: nil, accountPeer: nil,
            isCentered: false, isPreview: true, isStandalone: true, rank: nil, rankRole: nil
        )
    }
}

public func ayuMessageHistoryController(context: AccountContext, message: EngineRawMessage) -> ViewController {
    let revisions = AyuMessageArchive.get(mediaBox: context.account.postbox.mediaBox).revisions(message.id)
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        var entries: [AyuHistoryEntry] = []
        func append(_ text: String, message: EngineRawMessage? = nil) {
            entries.append(AyuHistoryEntry(stableId: Int32(entries.count), text: text, message: message, data: data))
        }
        append("Local history · Only versions saved on this device are shown.")
        for (index, revision) in revisions.enumerated() {
            let decoder = PostboxDecoder(buffer: MemoryBuffer(data: revision.payload))
            let media = decoder.decodeObjectArrayForKey("media").compactMap { $0 as? Media }
            let attributes = decoder.decodeObjectArrayForKey("attributes").compactMap { $0 as? MessageAttribute }
            let kind = revision.deleted ? "Deleted" : (index == 0 ? "Original" : "Edited")
            append(kind + " · " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(revision.capturedAt))))
            let id = MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: Int32(index + 1))
            let author = revision.senderId.flatMap { message.peers[PeerId($0)] } ?? message.author
            let restored = Message(
                stableId: UInt32(index + 1), stableVersion: 0, id: id, globallyUniqueId: nil,
                groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: revision.timestamp,
                flags: message.flags, tags: [], globalTags: [], localTags: [], customTags: [],
                forwardInfo: nil, author: author, text: revision.text, attributes: attributes,
                media: media, peers: message.peers, associatedMessages: message.associatedMessages,
                associatedMessageIds: [], associatedMedia: message.associatedMedia,
                associatedThreadInfo: nil, associatedStories: message.associatedStories
            )
            append("", message: restored)
        }
        let deleted = message.attributes.contains { $0 is AyuDeletedMessageAttribute }
        append(deleted ? "Deleted · Last saved version" : "Current version")
        let currentId = MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: Int32(revisions.count + 1))
        append("", message: message.withUpdatedId(id: currentId).withUpdatedStableId(stableId: UInt32(revisions.count + 1)))
        if revisions.isEmpty { append("No earlier versions saved on this device.") }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text("Message History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .plain, animateChanges: false), context))
    }
    return ItemListController(context: context, state: signal)
}
