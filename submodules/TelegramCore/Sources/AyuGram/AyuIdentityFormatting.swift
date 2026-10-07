import Foundation

public enum AyuIdentityKind {
    case name
    case username
    case phone
}

public enum AyuIdentityFormatting {
    public static func shouldHide(_ kind: AyuIdentityKind, preferences: AyuPreferences) -> Bool {
        guard preferences.streamerMode else { return false }
        switch kind {
        case .name: return preferences.hideNames
        case .username: return preferences.hideUsernames
        case .phone: return preferences.hidePhoneNumbers
        }
    }
}
