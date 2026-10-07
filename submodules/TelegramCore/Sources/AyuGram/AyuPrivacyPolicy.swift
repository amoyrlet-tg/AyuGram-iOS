import Foundation

public struct AyuPreferences: Codable, Equatable {
    public var ghostMode = false
    public var dontReadMessages = false
    public var dontReadStories = false
    public var dontSendActivity = false
    public var dontSendOnline = false
    public var autoOffline = true
    public var saveDeletedMessages = true
    public var saveEditHistory = true
    public var autoDeleteMessages = false
    public var autoDeleteDelay: Int32 = 180
    public var showNumericId = true
    public var showDcId = true

    public var suppressReads: Bool { self.ghostMode || self.dontReadMessages }
    public var suppressStories: Bool { self.ghostMode || self.dontReadStories }
    public var suppressActivity: Bool { self.ghostMode || self.dontSendActivity }
    public var suppressOnline: Bool { self.ghostMode || self.dontSendOnline }
}

enum AyuPrivacyPolicy {
    static let activeMethods: Set<String> = [
        "messages.sendMessage", "messages.sendMedia", "messages.sendMultiMedia",
        "messages.forwardMessages", "messages.sendInlineBotResult", "messages.editMessage",
        "messages.sendReaction", "messages.sendVote", "messages.sendPaidReaction",
        "messages.getBotCallbackAnswer", "messages.startBot", "messages.sendEncrypted",
        "messages.sendEncryptedFile", "phone.requestCall", "phone.acceptCall",
        "phone.confirmCall", "phone.joinGroupCall", "phone.createGroupCall",
        "stories.sendStory", "stories.sendReaction"
    ]
    static let readMethods: Set<String> = [
        "messages.readHistory", "channels.readHistory", "messages.readDiscussion",
        "messages.readMessageContents", "channels.readMessageContents", "messages.readMentions",
        "messages.readReactions", "messages.readEncryptedHistory", "messages.readSavedHistory"
    ]


    static func suppress(method: String, isOfflineStatus: Bool = false, preferences: AyuPreferences, explicitRead: Bool = false) -> Bool {
        if preferences.suppressReads && !explicitRead && self.readMethods.contains(method) { return true }
        if preferences.suppressStories && ["stories.readStories", "stories.incrementStoryViews"].contains(method) { return true }
        if preferences.suppressActivity && ["messages.setTyping", "messages.setEncryptedTyping"].contains(method) { return true }
        if preferences.suppressOnline && method == "account.updateStatus" && !isOfflineStatus { return true }
        return false
    }

    static func passiveOnline(foreground: Bool, preferences: AyuPreferences) -> Bool {
        return foreground && !preferences.suppressOnline
    }

    static func returnOfflineAfterAction(preferences: AyuPreferences) -> Bool {
        return preferences.suppressOnline || preferences.autoOffline
    }
}

final class AyuActivityCounter {
    private let lock = NSLock()
    private var count = 0

    var isIdle: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.count == 0
    }

    func begin() {
        self.lock.lock()
        self.count += 1
        self.lock.unlock()
    }

    func end() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        precondition(self.count > 0)
        self.count -= 1
        return self.count == 0
    }
}
