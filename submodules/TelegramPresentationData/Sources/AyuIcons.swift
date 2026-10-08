import UIKit

/// A split paper plane shared by preferences and the message submenu.
public func ayuPreferencesIcon(color: UIColor? = nil) -> UIImage? {
    let size = CGSize(width: 29.0, height: 29.0)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    if color == nil {
        context.setFillColor(UIColor(red: 0.55, green: 0.30, blue: 0.93, alpha: 1.0).cgColor)
        context.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7.0).cgPath)
        context.fillPath()
    }
    context.setFillColor((color ?? .white).cgColor)
    context.move(to: CGPoint(x: 5.0, y: 13.0))
    context.addLine(to: CGPoint(x: 24.0, y: 6.0))
    context.addLine(to: CGPoint(x: 13.0, y: 17.0))
    context.closePath()
    context.fillPath()
    context.move(to: CGPoint(x: 15.0, y: 18.0))
    context.addLine(to: CGPoint(x: 24.0, y: 8.0))
    context.addLine(to: CGPoint(x: 20.0, y: 24.0))
    context.closePath()
    context.fillPath()
    return UIGraphicsGetImageFromCurrentImageContext()
}
