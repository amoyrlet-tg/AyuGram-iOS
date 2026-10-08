import Foundation

public enum AyuIdentityKind: Equatable {
    case name
    case username
    case phone
    case phoneAndUsername
}

public enum AyuIdentityFormatting {
    public static func shouldHide(_ kind: AyuIdentityKind, preferences: AyuPreferences) -> Bool {
        guard preferences.streamerMode else { return false }
        switch kind {
        case .name: return false
        case .username: return preferences.hideUsernames
        case .phone: return preferences.hidePhoneNumbers
        case .phoneAndUsername: return preferences.hidePhoneNumbers || preferences.hideUsernames
        }
    }
}
