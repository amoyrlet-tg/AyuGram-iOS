import UIKit
import ObjectiveC
import TelegramCore
import SwiftSignalKit
import InvisibleInkDustNode

private var ayuStreamerBindingKey: UInt8 = 0

private final class AyuStreamerBinding: NSObject {
    weak var target: UIView?
    weak var contentView: UIView?
    let store: AyuPreferencesStore
    let kind: AyuIdentityKind
    let contentKey: String
    let disposable = MetaDisposable()
    let overlay = UIControl()
    let dust = InvisibleInkDustView(textNode: nil, enableAnimations: true)
    private var savedMask: CALayer?
    private var masked = false
    private var enabled = false
    private var revealed = false
    private var asking = false

    init(view: UIView, kind: AyuIdentityKind, store: AyuPreferencesStore, contentKey: String, contentView: UIView?) {
        self.target = view
        self.contentView = contentView ?? view
        self.store = store
        self.kind = kind
        self.contentKey = contentKey
        super.init()
        self.dust.isUserInteractionEnabled = false
        self.overlay.addSubview(self.dust)
        self.overlay.accessibilityLabel = "Hidden personal information"
        self.overlay.isAccessibilityElement = true
        self.overlay.addTarget(self, action: #selector(self.revealPressed), for: .touchUpInside)
        self.update(preferences: store.current)
        self.disposable.set((store.signal |> deliverOnMainQueue).start(next: { [weak self] preferences in
            self?.update(preferences: preferences)
        }))
    }

    func update(preferences: AyuPreferences) {
        let enabled = AyuIdentityFormatting.shouldHide(self.kind, preferences: preferences)
        if self.enabled != enabled { self.revealed = false }
        self.enabled = enabled
        self.layout()
    }

    func layout() {
        guard let target = self.target, let contentView = self.contentView else { return }
        if self.enabled && !self.revealed, let parent = target.superview {
            if !self.masked {
                self.savedMask = contentView.layer.mask
                contentView.layer.mask = CALayer()
                contentView.accessibilityElementsHidden = true
                self.masked = true
            }
            if self.overlay.superview !== parent {
                self.overlay.removeFromSuperview()
                parent.addSubview(self.overlay)
            }
            parent.bringSubviewToFront(self.overlay)
            self.overlay.frame = target.convert(target.bounds, to: parent)
            self.dust.frame = self.overlay.bounds
            let rect = CGRect(x: 0, y: 2, width: self.overlay.bounds.width, height: max(0, self.overlay.bounds.height - 4))
            self.dust.update(size: self.overlay.bounds.size, color: .secondaryLabel, textColor: .secondaryLabel, rects: [rect], wordRects: [rect])
        } else {
            self.restore()
        }
    }

    func restore() {
        if self.masked, let contentView = self.contentView {
            contentView.layer.mask = self.savedMask
            contentView.accessibilityElementsHidden = false
        }
        self.masked = false
        self.savedMask = nil
        self.overlay.removeFromSuperview()
    }

    @objc private func revealPressed() {
        guard !self.asking, let root = self.target?.window?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        self.asking = true
        let alert = UIAlertController(title: "Убрать блюр?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { [weak self] _ in self?.asking = false }))
        alert.addAction(UIAlertAction(title: "Убрать", style: .default, handler: { [weak self] _ in
            self?.asking = false
            self?.revealed = true
            self?.layout()
        }))
        presenter.present(alert, animated: true)
    }

    deinit {
        self.disposable.dispose()
        self.restore()
    }
}

public enum AyuStreamerMode {
    public static func isConcealed(_ view: UIView) -> Bool {
        guard let binding = objc_getAssociatedObject(view, &ayuStreamerBindingKey) as? AyuStreamerBinding else { return false }
        return binding.overlay.superview != nil
    }
    public static func unbind(from view: UIView) {
        (objc_getAssociatedObject(view, &ayuStreamerBindingKey) as? AyuStreamerBinding)?.restore()
        objc_setAssociatedObject(view, &ayuStreamerBindingKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    public static func bind(to view: UIView, kind: AyuIdentityKind, store: AyuPreferencesStore, contentKey: String = "", contentView: UIView? = nil) {
        if let binding = objc_getAssociatedObject(view, &ayuStreamerBindingKey) as? AyuStreamerBinding,
           binding.store === store, binding.kind == kind, binding.contentKey == contentKey {
            binding.layout()
            return
        }
        self.unbind(from: view)
        objc_setAssociatedObject(view, &ayuStreamerBindingKey, AyuStreamerBinding(view: view, kind: kind, store: store, contentKey: contentKey, contentView: contentView), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
