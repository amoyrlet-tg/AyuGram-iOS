import Foundation

public struct AyuPreferences: Codable, Equatable {
    public var ghostMode = false
    // These defaults only affect accounts which have not written preferences yet.
    public var dontReadMessages = true
    public var dontReadStories = true
    public var dontSendActivity = false
    public var dontSendOnline = true
    public var autoOffline = true
    public var saveDeletedMessages = true
    public var saveEditHistory = true
    public var archiveMedia = true
    public var streamerMode = false
    public var hideNames = true
    public var hideUsernames = true
    public var hidePhoneNumbers = true
    public var showTimestampSeconds = true
    public var autoDeleteMessages = false
    public var autoDeleteInPrivateChats = false
    public var autoDeleteDelay: Int32 = 180
    public var showNumericId = true
    public var showDcId = true
    public var keepReactionPickerOpen = false
    public var hideContactsTab = false
    public var hideCallsTab = false
    public var hideTabLabels = false
    public var compactTabBar = true
    public var foldersAtBottom = false

    public var sendActivityStatuses: Bool {
        get { !self.dontSendActivity }
        set { self.dontSendActivity = !newValue }
    }

    public var sendOnlineStatus: Bool {
        get { !self.dontSendOnline }
        set { self.dontSendOnline = !newValue }
    }

    public var suppressReads: Bool { self.ghostMode || self.dontReadMessages }
    public var suppressStories: Bool { self.ghostMode || self.dontReadStories }
    public var suppressActivity: Bool { self.ghostMode || self.dontSendActivity }
    public var suppressOnline: Bool { self.ghostMode || self.dontSendOnline }

    public var ghostModeActive: Bool {
        self.suppressReads && self.suppressStories && self.suppressOnline && self.suppressActivity && (self.ghostMode || self.autoOffline)
    }

    public mutating func setGhostModeEnabled(_ enabled: Bool) {
        self.ghostMode = enabled
        self.dontReadMessages = enabled
        self.dontReadStories = enabled
        self.dontSendOnline = enabled
        self.dontSendActivity = enabled
        self.autoOffline = enabled
    }

    public mutating func setGhostOption(_ keyPath: WritableKeyPath<AyuPreferences, Bool>, enabled: Bool) {
        // Materialize legacy master overrides before editing one option. The
        // master reflects the checkboxes, just like AyuGram Desktop.
        if self.ghostMode { self.setGhostModeEnabled(true) }
        self.ghostMode = false
        self[keyPath: keyPath] = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case ghostMode, dontReadMessages, dontReadStories, dontSendActivity, dontSendOnline, autoOffline
        case saveDeletedMessages, saveEditHistory, archiveMedia, streamerMode, hideNames, hideUsernames, hidePhoneNumbers, showTimestampSeconds
        case autoDeleteMessages, autoDeleteInPrivateChats, autoDeleteDelay, showNumericId, showDcId
        case keepReactionPickerOpen, hideContactsTab, hideCallsTab, hideTabLabels, compactTabBar
        case foldersAtBottom
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        self.ghostMode = try values.decodeIfPresent(Bool.self, forKey: .ghostMode) ?? self.ghostMode
        self.dontReadMessages = try values.decodeIfPresent(Bool.self, forKey: .dontReadMessages) ?? self.dontReadMessages
        self.dontReadStories = try values.decodeIfPresent(Bool.self, forKey: .dontReadStories) ?? self.dontReadStories
        self.dontSendActivity = try values.decodeIfPresent(Bool.self, forKey: .dontSendActivity) ?? self.dontSendActivity
        self.dontSendOnline = try values.decodeIfPresent(Bool.self, forKey: .dontSendOnline) ?? self.dontSendOnline
        self.autoOffline = try values.decodeIfPresent(Bool.self, forKey: .autoOffline) ?? self.autoOffline
        self.saveDeletedMessages = try values.decodeIfPresent(Bool.self, forKey: .saveDeletedMessages) ?? self.saveDeletedMessages
        self.saveEditHistory = try values.decodeIfPresent(Bool.self, forKey: .saveEditHistory) ?? self.saveEditHistory
        self.archiveMedia = try values.decodeIfPresent(Bool.self, forKey: .archiveMedia) ?? self.archiveMedia
        self.streamerMode = try values.decodeIfPresent(Bool.self, forKey: .streamerMode) ?? self.streamerMode
        self.hideNames = try values.decodeIfPresent(Bool.self, forKey: .hideNames) ?? self.hideNames
        self.hideUsernames = try values.decodeIfPresent(Bool.self, forKey: .hideUsernames) ?? self.hideUsernames
        self.hidePhoneNumbers = try values.decodeIfPresent(Bool.self, forKey: .hidePhoneNumbers) ?? self.hidePhoneNumbers
        self.showTimestampSeconds = try values.decodeIfPresent(Bool.self, forKey: .showTimestampSeconds) ?? self.showTimestampSeconds
        self.autoDeleteMessages = try values.decodeIfPresent(Bool.self, forKey: .autoDeleteMessages) ?? self.autoDeleteMessages
        self.autoDeleteInPrivateChats = try values.decodeIfPresent(Bool.self, forKey: .autoDeleteInPrivateChats) ?? self.autoDeleteInPrivateChats
        self.autoDeleteDelay = try values.decodeIfPresent(Int32.self, forKey: .autoDeleteDelay) ?? self.autoDeleteDelay
        self.showNumericId = try values.decodeIfPresent(Bool.self, forKey: .showNumericId) ?? self.showNumericId
        self.showDcId = try values.decodeIfPresent(Bool.self, forKey: .showDcId) ?? self.showDcId
        self.keepReactionPickerOpen = try values.decodeIfPresent(Bool.self, forKey: .keepReactionPickerOpen) ?? self.keepReactionPickerOpen
        self.hideContactsTab = try values.decodeIfPresent(Bool.self, forKey: .hideContactsTab) ?? self.hideContactsTab
        self.hideCallsTab = try values.decodeIfPresent(Bool.self, forKey: .hideCallsTab) ?? self.hideCallsTab
        self.hideTabLabels = try values.decodeIfPresent(Bool.self, forKey: .hideTabLabels) ?? self.hideTabLabels
        self.compactTabBar = try values.decodeIfPresent(Bool.self, forKey: .compactTabBar) ?? self.compactTabBar
        self.foldersAtBottom = try values.decodeIfPresent(Bool.self, forKey: .foldersAtBottom) ?? self.foldersAtBottom
    }
}

public enum AyuPrivacyPolicy {
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
    static let storyReadMethods: Set<String> = ["stories.readStories", "stories.incrementStoryViews"]


    static func suppress(method: String, isOfflineStatus: Bool = false, preferences: AyuPreferences, explicitRead: Bool = false) -> Bool {
        // A request's call site is not a privacy boundary. Automatic opening,
        // consumption and sync paths used to flag themselves as explicit reads.
        if preferences.suppressReads && self.readMethods.contains(method) { return true }
        if preferences.suppressStories && self.storyReadMethods.contains(method) { return true }
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
