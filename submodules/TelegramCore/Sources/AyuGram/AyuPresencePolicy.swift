import Foundation

/// Activity and online presence are separate MTProto operations. Keep that
/// separation explicit so typing never promotes an account to online.
public enum AyuPresencePolicy {
    public static func allowsActivity(_ preferences: AyuPreferences) -> Bool {
        !preferences.suppressActivity
    }

    public static func allowsOnlinePresence(_ preferences: AyuPreferences) -> Bool {
        !preferences.suppressOnline
    }

    public static func shouldReturnOffline(_ preferences: AyuPreferences) -> Bool {
        preferences.suppressOnline || preferences.autoOffline
    }
}
