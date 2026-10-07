import Foundation
import Postbox
import SwiftSignalKit

public final class AyuDeletedMessageAttribute: MessageAttribute {
    public let timestamp: Int32
    public var associatedPeerIds: [PeerId] { [] }
    public init(timestamp: Int32) { self.timestamp = timestamp }
    public init(decoder: PostboxDecoder) { self.timestamp = decoder.decodeInt32ForKey("t", orElse: 0) }
    public func encode(_ encoder: PostboxEncoder) { encoder.encodeInt32(self.timestamp, forKey: "t") }
}

public struct AyuMessageRevision: Codable {
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public let timestamp: Int32
    public let capturedAt: Int32
    public let deleted: Bool
    public let text: String
    public let payload: Data
    public let senderId: Int64?
    public let mediaSummary: String?

    public var id: MessageId {
        MessageId(peerId: PeerId(self.peerId), namespace: self.namespace, id: self.messageId)
    }
}

public final class AyuMessageArchive {
    private static let registryLock = NSLock()
    private static var registry: [String: AyuMessageArchive] = [:]
    private let lock = NSLock()
    private let directory: URL

    public static func get(mediaBox: MediaBox) -> AyuMessageArchive {
        self.registryLock.lock()
        defer { self.registryLock.unlock() }
        let path = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("ayugram-cache").path
        if let result = self.registry[path] { return result }
        let result = AyuMessageArchive(path: path)
        self.registry[path] = result
        return result
    }

    private init(path: String) { self.directory = URL(fileURLWithPath: path, isDirectory: true) }

    private func file(_ id: MessageId) -> URL {
        self.directory.appendingPathComponent("\(id.peerId.toInt64())_\(id.namespace)_\(id.id).json")
    }

    public func revisions(_ id: MessageId) -> [AyuMessageRevision] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load(id)
    }

    private func load(_ id: MessageId) -> [AyuMessageRevision] {
        guard let data = try? Data(contentsOf: self.file(id)) else { return [] }
        return (try? JSONDecoder().decode([AyuMessageRevision].self, from: data)) ?? []
    }

    @discardableResult
    func capture(_ message: Message, deleted: Bool) -> Bool {
        guard message.id.namespace == Namespaces.Message.Cloud,
              message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              !message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        let encoder = PostboxEncoder()
        encoder.encodeObjectArrayWithEncoder(message.attributes, forKey: "attributes", encoder: { attribute, encoder in
            attribute.encode(encoder)
        })
        encoder.encodeObjectArrayWithEncoder(message.media, forKey: "media", encoder: { media, encoder in
            media.encode(encoder)
        })
        let mediaSummary = message.media.isEmpty ? nil : message.media.map { String(describing: type(of: $0)) }.joined(separator: ", ")
        let revision = AyuMessageRevision(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, timestamp: message.timestamp, capturedAt: Int32(Date().timeIntervalSince1970), deleted: deleted, text: message.text, payload: encoder.makeData(), senderId: message.author?.id.toInt64(), mediaSummary: mediaSummary)
        var revisions = self.load(message.id)
        if let last = revisions.last, last.text == revision.text && last.payload == revision.payload && last.deleted == deleted { return true }
        revisions.append(revision)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var url = self.directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try JSONEncoder().encode(revisions).write(to: self.file(message.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            Logger.shared.log("AyuGram", "Unable to write message history: \(error)")
            return false
        }
    }

    func retainDeleted(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
        return ids.filter { id in
            guard let message = transaction.getMessage(id) else { return true }
            if message.attributes.contains(where: { $0 is AyuDeletedMessageAttribute }) { return false }
            guard self.capture(message, deleted: true) else { return true }
            transaction.updateMessage(id, update: { current in
                var attributes = current.attributes
                attributes.append(AyuDeletedMessageAttribute(timestamp: Int32(Date().timeIntervalSince1970)))
                return .update(StoreMessage(id: current.id, customStableId: nil, globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey, threadId: current.threadId, timestamp: current.timestamp, flags: StoreMessageFlags(current.flags), tags: current.tags, globalTags: current.globalTags, localTags: current.localTags, forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: current.author?.id, text: current.text, attributes: attributes, media: current.media))
            })
            return false
        }
    }

    public func clear(postbox: Postbox) -> Signal<Bool, NoError> {
        return postbox.transaction { transaction -> Bool in
            self.lock.lock()
            defer { self.lock.unlock() }
            do {
                guard FileManager.default.fileExists(atPath: self.directory.path) else { return true }
                let files = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
                for file in files where file.pathExtension == "json" {
                    let revisions = try JSONDecoder().decode([AyuMessageRevision].self, from: Data(contentsOf: file))
                    if let id = revisions.last?.id, let message = transaction.getMessage(id), message.attributes.contains(where: { $0 is AyuDeletedMessageAttribute }) {
                        transaction.deleteMessages([id], forEachMedia: { _ in })
                    }
                    try FileManager.default.removeItem(at: file)
                }
                return true
            } catch {
                Logger.shared.log("AyuGram", "Unable to clear history: \(error)")
                return false
            }
        }
    }

    public func storageSize() -> Int64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { result, url in
            result + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

public func ayuBotAPIId(_ id: PeerId) -> Int64? {
    switch id.namespace {
    case Namespaces.Peer.CloudUser: return id.id._internalGetInt64Value()
    case Namespaces.Peer.CloudGroup: return -id.id._internalGetInt64Value()
    case Namespaces.Peer.CloudChannel: return -1_000_000_000_000 - id.id._internalGetInt64Value()
    default: return nil
    }
}
