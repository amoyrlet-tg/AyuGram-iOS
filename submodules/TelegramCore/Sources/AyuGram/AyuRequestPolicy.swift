import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit

final class AyuRequestPolicy {
    static let activeMethods = AyuPrivacyPolicy.activeMethods
    static let readMethods = AyuPrivacyPolicy.readMethods

    static func suppress(_ method: FunctionDescription, preferences: AyuPreferences, explicitRead: Bool) -> Bool {
        var isOfflineStatus = false
        for (key, parameter) in method.parameters where key == "offline" {
            if let value = parameter.value as? Api.Bool, case .boolTrue = value {
                isOfflineStatus = true
            }
        }
        return AyuPrivacyPolicy.suppress(method: method.name, isOfflineStatus: isOfflineStatus, preferences: preferences, explicitRead: explicitRead)
    }
}

final class AyuActivityTracker {
    let ended = ValuePipe<Void>()
    private let counter = AyuActivityCounter()
    var isIdle: Bool { self.counter.isIdle }

    func begin() -> Disposable {
        self.counter.begin()
        return ActionDisposable { [weak self] in
            guard let self = self else { return }
            let finished = self.counter.end()
            if finished { self.ended.putNext(()) }
        }
    }
}

extension Network {
    func ayuReadHistory(peer: Peer, index: MessageIndex) {
        if let channel = apiInputChannel(peer) {
            let _ = self.request(Api.functions.channels.readHistory(channel: channel, maxId: index.id.id), ayuExplicitRead: true).startStandalone()
        } else if let encrypted = apiInputSecretChat(peer) {
            let _ = self.request(Api.functions.messages.readEncryptedHistory(peer: encrypted, maxDate: index.timestamp), ayuExplicitRead: true).startStandalone()
        } else if let inputPeer = apiInputPeer(peer) {
            let _ = self.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: index.id.id), ayuExplicitRead: true).startStandalone(next: { [weak self] result in
                if case let .affectedMessages(data) = result {
                    self?.ayuReadStateUpdates.putNext((data.pts, data.ptsCount))
                }
            })
        }
    }
}
