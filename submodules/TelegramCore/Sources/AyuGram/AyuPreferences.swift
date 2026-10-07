import Foundation
import SwiftSignalKit

public final class AyuPreferencesStore {
    private let file: URL?
    private let lock = NSLock()
    private var value: AyuPreferences
    private let promise: ValuePromise<AyuPreferences>

    public init(mediaBoxPath: String? = nil) {
        let file = mediaBoxPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("ayugram-preferences.json") }
        self.file = file
        let value = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(AyuPreferences.self, from: $0) } ?? AyuPreferences()
        self.value = value
        self.promise = ValuePromise(value, ignoreRepeated: true)
    }

    public var current: AyuPreferences {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let file = self.file, let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(AyuPreferences.self, from: data) {
            self.value = value
        }
        return self.value
    }

    public var signal: Signal<AyuPreferences, NoError> { self.promise.get() }

    @discardableResult
    public func update(_ f: (inout AyuPreferences) -> Void) -> Bool {
        self.lock.lock()
        var value = self.value
        f(&value)
        value.autoDeleteDelay = max(10, min(604800, value.autoDeleteDelay))
        if let file = self.file {
            do {
                try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                self.lock.unlock()
                return false
            }
        }
        self.value = value
        self.lock.unlock()
        self.promise.set(value)
        return true
    }
}
