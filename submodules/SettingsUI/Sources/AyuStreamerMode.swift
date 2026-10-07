import UIKit
import TelegramCore

/// Rendering-only building block for identity labels. Callers retain the original
/// text and add this view above the label, so toggling Streamer Mode never mutates
/// peer, account or message data.
public enum AyuStreamerMode {
    public static func shouldObscure(_ kind: AyuIdentityKind, preferences: AyuPreferences) -> Bool {
        AyuIdentityFormatting.shouldHide(kind, preferences: preferences)
    }

    public static func applySpoiler(to view: UIView, enabled: Bool) {
        let tag = 0x415955
        view.viewWithTag(tag)?.removeFromSuperview()
        guard enabled else { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.tag = tag
        blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = 4.0
        blur.clipsToBounds = true
        blur.frame = view.bounds.insetBy(dx: -1.0, dy: -1.0)
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blur)
    }
}
