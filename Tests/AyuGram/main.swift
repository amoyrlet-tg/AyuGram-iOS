import Foundation

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    assertions += 1
}

var normal = AyuPreferences()
normal.autoOffline = false
check(normal.autoDeleteDelay == 180, "Default delay must be three minutes")
check(!normal.sendOnlineStatus, "Online status must default to off")
check(normal.sendActivityStatuses, "Activity statuses must default to on")
check(normal.dontReadMessages && normal.dontReadStories, "Read protection must default to on")
normal.dontReadMessages = false
normal.dontReadStories = false
normal.dontSendOnline = false
check(AyuPrivacyPolicy.passiveOnline(foreground: true, preferences: normal), "Normal presence must still work")
check(!AyuPrivacyPolicy.passiveOnline(foreground: false, preferences: normal), "Background cannot activate presence")
var ghost = normal
ghost.ghostMode = true
for foreground in [false, true] {
    check(!AyuPrivacyPolicy.passiveOnline(foreground: foreground, preferences: ghost), "Ghost must never activate passive presence")
}
for method in ["messages.getHistory", "messages.getDialogs", "users.getFullUser", "channels.getFullChannel", "updates.getDifference", "upload.getFile"] {
    check(!AyuPrivacyPolicy.suppress(method: method, preferences: ghost), "Ghost must preserve passive RPCs: \(method)")
    check(!AyuPrivacyPolicy.activeMethods.contains(method), "Passive RPC must not start activity: \(method)")
}
for method in ["messages.readHistory", "channels.readHistory", "messages.readDiscussion", "messages.readMessageContents", "channels.readMessageContents", "messages.readEncryptedHistory", "messages.readSavedHistory", "messages.readMentions", "messages.readReactions"] {
    check(AyuPrivacyPolicy.suppress(method: method, preferences: ghost), "Ghost must block read receipt: \(method)")
    check(AyuPrivacyPolicy.suppress(method: method, preferences: ghost, explicitRead: true), "Explicit reads must not bypass Ghost Mode: \(method)")
    check(!AyuPrivacyPolicy.suppress(method: method, preferences: normal), "Normal reads must remain possible")
}
for method in ["stories.readStories", "stories.incrementStoryViews", "messages.setTyping", "messages.setEncryptedTyping"] {
    check(AyuPrivacyPolicy.suppress(method: method, preferences: ghost), "Ghost leaked an activity RPC")
    check(AyuPrivacyPolicy.suppress(method: method, preferences: ghost, explicitRead: true), "Manual message read must not unlock unrelated activity")
}
check(AyuPrivacyPolicy.suppress(method: "account.updateStatus", preferences: ghost), "Ghost leaked online")
check(!AyuPrivacyPolicy.suppress(method: "account.updateStatus", isOfflineStatus: true, preferences: ghost), "Offline must remain allowed")
for method in ["messages.sendMessage", "messages.sendMedia", "messages.sendReaction", "phone.requestCall", "phone.acceptCall"] {
    check(AyuPrivacyPolicy.activeMethods.contains(method), "Explicit activity untracked")
    check(!AyuPrivacyPolicy.suppress(method: method, preferences: ghost), "Ghost must not prevent explicit actions")
}
check(AyuPrivacyPolicy.returnOfflineAfterAction(preferences: ghost), "Ghost must return offline even when Auto Offline is off")
check(!AyuPrivacyPolicy.returnOfflineAfterAction(preferences: normal), "Normal mode must respect Auto Offline")
var independent = normal
independent.dontReadMessages = true
check(AyuPrivacyPolicy.suppress(method: "messages.readHistory", preferences: independent), "Read switch ineffective")
check(!AyuPrivacyPolicy.suppress(method: "stories.readStories", preferences: independent), "Message switch must not alter story setting")
independent.dontReadStories = true
independent.dontSendActivity = true
independent.dontSendOnline = true
check(AyuPrivacyPolicy.suppress(method: "stories.readStories", preferences: independent), "Story switch ineffective")
check(AyuPrivacyPolicy.suppress(method: "messages.setTyping", preferences: independent), "Activity switch ineffective")
check(!AyuPrivacyPolicy.passiveOnline(foreground: true, preferences: independent), "Online switch ineffective")
let encoded = try JSONEncoder().encode(independent)
let decoded = try JSONDecoder().decode(AyuPreferences.self, from: encoded)
check(decoded == independent, "Preferences must survive restart")
var toggles = AyuPreferences()
toggles.setGhostModeEnabled(true)
check(toggles.ghostModeActive, "Master must enable all five protections")
toggles.setGhostOption(\.dontReadMessages, enabled: false)
check(!toggles.suppressReads, "Turning Read messages on must override a previously enabled master")
check(toggles.suppressStories, "Enabling message reads must preserve story protection")
check(!toggles.ghostModeActive, "Master must reflect partial protection")
toggles.setGhostOption(\.dontReadMessages, enabled: true)
check(toggles.ghostModeActive, "Restoring the fifth protection must activate the master indicator")
toggles.setGhostModeEnabled(false)
check(!toggles.suppressReads && !toggles.suppressStories, "Turning the master off must restore normal message and story reading")
check(!toggles.suppressActivity && !toggles.suppressOnline && !toggles.autoOffline, "Master off must turn all protections off")
toggles.setGhostOption(\.dontReadStories, enabled: true)
check(toggles.suppressStories && !toggles.suppressReads, "Turning Read stories off must block only story reads")
toggles.setGhostOption(\.dontReadStories, enabled: false)
check(!toggles.suppressStories, "Turning Read stories on must allow story reads again")
let togglesRestored = try JSONDecoder().decode(AyuPreferences.self, from: JSONEncoder().encode(toggles))
check(togglesRestored == toggles, "Changed switches must survive restart")
var appearance = AyuPreferences()
appearance.hideContactsTab = true
appearance.hideCallsTab = true
appearance.hideTabLabels = true
appearance.compactTabBar = false
appearance.keepReactionPickerOpen = true
appearance.foldersAtBottom = true
appearance.autoDeleteInPrivateChats = true
let restoredAppearance = try JSONDecoder().decode(AyuPreferences.self, from: JSONEncoder().encode(appearance))
check(restoredAppearance == appearance, "Bottom bar and reaction settings must survive restart")
let legacyPreferences = try JSONDecoder().decode(AyuPreferences.self, from: Data("{}".utf8))
check(!legacyPreferences.hideContactsTab && !legacyPreferences.hideCallsTab && !legacyPreferences.hideTabLabels, "Existing users must keep navigation tabs until they choose to hide them")
check(!legacyPreferences.keepReactionPickerOpen, "Persistent reactions must be opt-in")
check(!legacyPreferences.foldersAtBottom, "Moving folders must be opt-in")
check(!legacyPreferences.autoDeleteInPrivateChats, "Auto-delete must default to groups only")
let activity = AyuActivityCounter()
check(activity.isIdle, "Presence must start idle")
activity.begin()
activity.begin()
check(!activity.isIdle, "Concurrent actions must hold activity")
check(!activity.end(), "First completion must not return offline while another action runs")
check(activity.end(), "Final completion must return offline")
check(activity.isIdle, "Activity must be released after completion")
activity.begin()
DispatchQueue.concurrentPerform(iterations: 1000) { _ in
    activity.begin()
    _ = activity.end()
}
check(!activity.isIdle, "Concurrent requests must not release the outstanding action")
check(activity.end(), "Activity counter leaked a request")
print("AyuGram privacy policy: \(assertions) assertions passed")
