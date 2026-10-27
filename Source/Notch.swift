import AppKit

/// Pop-ups grow out of the MacBook notch when the main screen has one, like a Dynamic Island.
enum Notch {
    /// Width of the outward curves where the island meets the menu bar.
    static let ear: CGFloat = 12
    /// The notch cut-out on the main screen, in screen coordinates; nil on screens without a notch.
    static var current: NSRect? {
        guard let screen = NSScreen.main, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX else { return nil }
        let height = screen.safeAreaInsets.top
        return NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }
    /// Panel frame for an island of `size`, hanging from the top of the screen, centred on the notch.
    static func frame(for size: NSSize, notch: NSRect) -> NSRect {
        NSRect(x: notch.midX - size.width / 2 - ear, y: notch.maxY - size.height, width: size.width + 2 * ear, height: size.height)
    }
    /// The island in a flipped view: `progress` 0 is exactly notch-sized (hidden behind the real notch), 1 is fully open.
    static func shape(in bounds: NSRect, notch: NSSize, progress: CGFloat) -> NSBezierPath {
        let p = max(0, min(1, progress))
        let fullWidth = bounds.width - 2 * ear
        let w = notch.width + (fullWidth - notch.width) * p, h = notch.height + (bounds.height - notch.height) * p
        let r = 8 + 14 * p, e = ear * max(0.35, p)
        let x0 = bounds.midX - w / 2, x1 = bounds.midX + w / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x0 - e, y: 0))
        path.curve(to: NSPoint(x: x0, y: e), controlPoint1: NSPoint(x: x0 - e * 0.25, y: 0), controlPoint2: NSPoint(x: x0, y: e * 0.25))
        path.line(to: NSPoint(x: x0, y: h - r))
        path.curve(to: NSPoint(x: x0 + r, y: h), controlPoint1: NSPoint(x: x0, y: h - r * 0.45), controlPoint2: NSPoint(x: x0 + r * 0.45, y: h))
        path.line(to: NSPoint(x: x1 - r, y: h))
        path.curve(to: NSPoint(x: x1, y: h - r), controlPoint1: NSPoint(x: x1 - r * 0.45, y: h), controlPoint2: NSPoint(x: x1, y: h - r * 0.45))
        path.line(to: NSPoint(x: x1, y: e))
        path.curve(to: NSPoint(x: x1 + e, y: 0), controlPoint1: NSPoint(x: x1, y: e * 0.25), controlPoint2: NSPoint(x: x1 + e * 0.25, y: 0))
        path.close()
        return path
    }
    /// The paper sheet set into the island: below the notch, inside a thin black rim.
    static func paper(in bounds: NSRect, notch: NSSize, progress: CGFloat) -> NSBezierPath {
        let p = max(0, min(1, progress)), rim: CGFloat = 5
        let w = notch.width + (bounds.width - 2 * ear - notch.width) * p, h = notch.height + (bounds.height - notch.height) * p
        let rect = NSRect(x: bounds.midX - w / 2 + rim, y: notch.height + 1, width: max(0, w - 2 * rim), height: max(0, h - notch.height - 1 - rim))
        let r = max(4, 8 + 14 * p - rim)
        return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    }
    /// Black band and rim, then the paper sheet fading in as the island opens.
    static func drawIsland(in bounds: NSRect, notch: NSSize, progress: CGFloat) {
        NSColor.black.setFill(); shape(in: bounds, notch: notch, progress: progress).fill()
        let alpha = min(1, max(0, (progress - 0.3) / 0.4))
        guard alpha > 0 else { return }
        let sheet = paper(in: bounds, notch: notch, progress: progress)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        Artwork.sheet.setFill(); sheet.fill()
        sheet.addClip(); Artwork.paperGrain(sheet.bounds, strength: 0.8)
        // A faint hatched shade under the notch, as if the sheet slides out from beneath it.
        Artwork.hatch(in: NSRect(x: sheet.bounds.minX, y: sheet.bounds.minY, width: sheet.bounds.width, height: 6), opacity: 0.18, spacing: 3, width: 0.6)
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Content fades in only once the island has mostly opened, so it never shows squeezed.
    static func contentAlpha(_ progress: CGFloat) -> CGFloat { max(0, min(1, (progress - 0.55) / 0.35)) }
    static func panel(frame: NSRect) -> NSPanel {
        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]; panel.appearance = NSAppearance(named: .aqua)
        panel.isReleasedWhenClosed = false
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// Lets the island sit over the menu bar; ordinary windows are pushed below it.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
