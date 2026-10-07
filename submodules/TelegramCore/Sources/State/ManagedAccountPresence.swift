import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var wasOnline: Bool = false
    private var activityDisposable: Disposable?
    private var preferences = AyuPreferences()
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        self.shouldKeepOnlinePresenceDisposable = (combineLatest(shouldKeepOnlinePresence, network.ayuPreferences.signal)
        |> distinctUntilChanged(isEqual: { $0.0 == $1.0 && $0.1 == $1.1 })
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            let (foreground, preferences) = value
            let changed = self.preferences != preferences
            self.preferences = preferences
            let online = foreground && AyuPresencePolicy.allowsOnlinePresence(preferences)
            if self.wasOnline != online || changed || preferences.suppressOnline {
                self.wasOnline = online
                self.updatePresence(online)
            }
        })
        self.activityDisposable = (network.ayuActivity.ended.signal()
        |> deliverOn(self.queue)).start(next: { [weak self] _ in
            guard let self = self else { return }
            if self.network.ayuActivity.isIdle && AyuPresencePolicy.shouldReturnOffline(self.preferences) {
                self.wasOnline = false
                self.updatePresence(false)
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.activityDisposable?.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ requestedOnline: Bool) {
        let isOnline = requestedOnline && AyuPresencePolicy.allowsOnlinePresence(self.network.ayuPreferences.current)
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> retryRequest
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
