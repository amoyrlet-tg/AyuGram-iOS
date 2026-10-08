import UIKit
import ObjectiveC
import TelegramCore
import SwiftSignalKit

private var ayuStreamerBindingKey: UInt8 = 0

private final class AyuStreamerBinding {
    let store: AyuPreferencesStore
    let kind: AyuIdentityKind
    let disposable = MetaDisposable()

    init(view: UIView, kind: AyuIdentityKind, store: AyuPreferencesStore) {
        self.store = store
        self.kind = kind
        self.disposable.set((store.signal |> deliverOnMainQueue).start(next: { [weak view] preferences in
            guard let view else { return }
            AyuStreamerMode.applySpoiler(to: view, enabled: AyuIdentityFormatting.shouldHide(kind, preferences: preferences))
        }))
    }

    deinit { self.disposable.dispose() }
}

public enum AyuStreamerMode {
    public static func unbind(from view: UIView) {
        objc_setAssociatedObject(view, &ayuStreamerBindingKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.applySpoiler(to: view, enabled: false)
    }

    public static func bind(to view: UIView, kind: AyuIdentityKind, store: AyuPreferencesStore) {
        if let binding = objc_getAssociatedObject(view, &ayuStreamerBindingKey) as? AyuStreamerBinding,
           binding.store === store, binding.kind == kind {
            return
        }
        self.applySpoiler(to: view, enabled: AyuIdentityFormatting.shouldHide(kind, preferences: store.current))
        objc_setAssociatedObject(view, &ayuStreamerBindingKey, AyuStreamerBinding(view: view, kind: kind, store: store), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    public static func applySpoiler(to view: UIView, enabled: Bool) {
        let tag = 0x415955
        view.accessibilityElementsHidden = enabled
        if !enabled {
            view.viewWithTag(tag)?.removeFromSuperview()
            return
        }
        if view.viewWithTag(tag) != nil { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.tag = tag
        blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = 5.0
        blur.clipsToBounds = true
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blur)
    }
}
