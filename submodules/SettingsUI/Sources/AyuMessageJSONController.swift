import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext

public func ayuMessageJSONController(context: AccountContext, message: Message) -> ViewController {
    return AyuMessageJSONController(context: context, message: message)
}

private final class AyuMessageJSONController: ViewController {
    private let presentationData: PresentationData
    private let json: String
    private let textView = UITextView()

    init(context: AccountContext, message: Message) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        // This is the local Postbox representation, not a fabricated API reply.
        // Decimal strings preserve 64-bit identifiers in JavaScript viewers.
        var object: [String: Any] = [
            "source": "local_message",
            "id": message.id.id,
            "namespace": message.id.namespace,
            "peer_id": String(message.id.peerId.toInt64()),
            "timestamp": message.timestamp,
            "text": message.text,
            "incoming": message.flags.contains(.Incoming),
            "attributes": message.attributes.map { attribute -> [String: Any] in
                let encoder = PostboxEncoder()
                attribute.encode(encoder)
                return ["type": String(describing: type(of: attribute)), "postbox_base64": encoder.makeData().base64EncodedString()]
            },
            "media": message.media.map { media -> [String: Any] in
                let encoder = PostboxEncoder()
                media.encode(encoder)
                return ["type": String(describing: type(of: media)), "postbox_base64": encoder.makeData().base64EncodedString()]
            }
        ]
        if let author = message.author { object["sender_id"] = String(author.id.toInt64()) }
        if let groupingKey = message.groupingKey { object["grouping_key"] = String(groupingKey) }
        if let threadId = message.threadId { object["thread_id"] = String(threadId) }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            self.json = text
        } else {
            self.json = "{}"
        }
        let data = self.presentationData
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: data.theme), strings: NavigationBarStrings(back: data.strings.Common_Back, close: data.strings.Common_Close)))
        self.title = "Message JSON"
        self.statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy JSON", style: .plain, target: self, action: #selector(self.copyJSON))
    }

    required init(coder: NSCoder) { preconditionFailure() }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.textView.backgroundColor = .clear
        self.textView.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.textView.tintColor = self.presentationData.theme.list.itemAccentColor
        self.textView.font = UIFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
        self.textView.isEditable = false
        self.textView.isSelectable = true
        self.textView.alwaysBounceVertical = true
        self.textView.contentInsetAdjustmentBehavior = .never
        self.textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 20, right: 12)
        self.textView.text = self.json
        self.displayNode.view.addSubview(self.textView)
        super.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: self.textView, frame: CGRect(x: layout.safeInsets.left, y: top, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: max(0, layout.size.height - top)))
        self.textView.contentInset.bottom = layout.intrinsicInsets.bottom
    }

    @objc private func copyJSON() {
        UIPasteboard.general.string = self.json
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
