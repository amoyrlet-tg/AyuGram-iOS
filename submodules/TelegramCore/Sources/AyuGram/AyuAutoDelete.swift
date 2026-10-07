import Foundation
import Postbox
import SwiftSignalKit

private struct AyuAutoDeleteEntry: Codable {
    let peerId: Int64
    let namespace: Int32
    let messageId: Int32
    let deadline: Int64
    var id: MessageId { MessageId(peerId: PeerId(self.peerId), namespace: self.namespace, id: self.messageId) }
}

final class AyuAutoDeleteQueue {
    private static let lock = NSLock()
    private let file: URL

    init(mediaBox: MediaBox) {
        self.file = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("ayugram-auto-delete.json")
    }

    private func read() -> [AyuAutoDeleteEntry] {
        guard let data = try? Data(contentsOf: self.file) else { return [] }
        return (try? JSONDecoder().decode([AyuAutoDeleteEntry].self, from: data)) ?? []
    }

    private func write(_ entries: [AyuAutoDeleteEntry]) {
        do {
            try JSONEncoder().encode(entries).write(to: self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger.shared.log("AyuGram", "Unable to save auto-delete queue: \(error)")
        }
    }

    func schedule(id: MessageId, preferences: AyuPreferences) {
        guard preferences.autoDeleteMessages, id.namespace == Namespaces.Message.Cloud, id.peerId.namespace != Namespaces.Peer.SecretChat else { return }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var entries = self.read()
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(AyuAutoDeleteEntry(peerId: id.peerId.toInt64(), namespace: id.namespace, messageId: id.id, deadline: Int64(Date().timeIntervalSince1970) + Int64(preferences.autoDeleteDelay)))
        self.write(entries)
    }

    func due() -> [MessageId] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let now = Int64(Date().timeIntervalSince1970)
        return self.read().filter { $0.deadline <= now }.map { $0.id }
    }

    func remove(_ ids: Set<MessageId>) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        self.write(self.read().filter { !ids.contains($0.id) })
    }
}

func managedAyuAutoDelete(postbox: Postbox, network: Network, stateManager: AccountStateManager) -> Signal<Void, NoError> {
    return Signal { _ in
        let queue = Queue(name: "AyuGram.AutoDelete")
        let jobs = AyuAutoDeleteQueue(mediaBox: postbox.mediaBox)
        let disposable = MetaDisposable()
        let tick = {
            guard network.ayuPreferences.current.autoDeleteMessages else { return }
            let ids = jobs.due()
            guard !ids.isEmpty else { return }
            disposable.set((postbox.transaction { transaction -> Void in
                deleteMessagesInteractively(transaction: transaction, stateManager: stateManager, postbox: postbox, messageIds: ids, type: .forEveryone, deleteAllInGroup: false, removeIfPossiblyDelivered: false)
            }).start(completed: { jobs.remove(Set(ids)) }))
        }
        let timer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: tick, queue: queue)
        timer.start()
        queue.async { tick() }
        return ActionDisposable {
            timer.invalidate()
            disposable.dispose()
        }
    }
}
