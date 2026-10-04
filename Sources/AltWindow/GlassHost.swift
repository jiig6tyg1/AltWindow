import AppKit
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Native Liquid Glass on macOS 26+, with real backdrop blur on older systems.
func glassHost<Content: View>(_ content: Content, radius: CGFloat = 26, size: NSSize? = nil) -> NSView {
    let host = NSHostingView(rootView: content)
    let initialSize = size ?? host.fittingSize
    // The panel owns its geometry. Intrinsic SwiftUI sizing would collapse a
    // headerless lazy grid to the minimum width of a single card.
    host.sizingOptions = []
    host.setFrameSize(initialSize)
    host.autoresizingMask = [.width, .height]
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView(frame: host.frame)
        glass.style = .regular
        glass.cornerRadius = radius
        glass.contentView = host
        return glass
    } else {
        let blur = NSVisualEffectView(frame: host.frame)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.masksToBounds = true
        blur.addSubview(host)
        return blur
    }
}

struct GlassControl: ViewModifier {
    var active = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(active ? .cyan.opacity(0.22) : .clear), in: .rect(cornerRadius: 14))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
