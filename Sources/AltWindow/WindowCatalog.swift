import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowItem: Identifiable {
    let id: String
    let pid: pid_t
    let element: AXUIElement
    let title: String
    let appName: String
    let icon: NSImage
    let windowID: CGWindowID?
    let minimized: Bool
    var bounds: CGRect = .zero
}

enum ThumbnailState: Equatable {
    case loading, ready, permissionRequired, minimized, unavailable, demo
    var label: String {
        switch self {
        case .loading: return "プレビューを取得中…"
        case .ready: return ""
        case .permissionRequired: return "画面収録の許可が必要です"
        case .minimized: return "最小化されています"
        case .unavailable: return "プレビューを取得できません"
        case .demo: return "デモ用ウィンドウ"
        }
    }
}

func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? T
}

final class WindowCatalog {
    @MainActor static var screenshotRequests = 0
    private let queue = DispatchQueue(label: "AltWindow.catalog", qos: .userInitiated)
    private var refreshing = false
    private var icons: [pid_t: NSImage] = [:] // Confined to queue, one small bitmap per app.

    // Called on the main queue; expensive accessibility queries run serially off it.
    func refresh(completion: @escaping ([WindowItem], String?) -> Void) {
        guard !refreshing, AXIsProcessTrusted() else { return }
        refreshing = true
        let runningApps = NSWorkspace.shared.runningApplications
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            let apps = runningApps.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
            }
            let livePIDs = Set(apps.map(\.processIdentifier))
            self.icons = self.icons.filter { livePIDs.contains($0.key) }
            let cgWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let candidates: [WindowCandidate] = cgWindows.compactMap { entry in
                guard (entry[kCGWindowLayer as String] as? Int) == 0,
                      let id = entry[kCGWindowNumber as String] as? UInt32,
                      let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                      let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
                return WindowCandidate(id: id, pid: pid, title: entry[kCGWindowName as String] as? String ?? "", bounds: bounds)
            }
            var result: [WindowItem] = []
            var focusedID: String?
            for app in apps {
                let icon: NSImage
                if let cached = self.icons[app.processIdentifier] { icon = cached }
                else {
                    var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
                    let original = app.icon
                    if let cg = original?.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                        icon = PreviewImage.make(cg, longestEdge: 64) ?? NSImage()
                    } else { icon = NSImage() }
                    self.icons[app.processIdentifier] = icon
                }
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(axApp, 0.15)
                guard let windows: [AXUIElement] = axValue(axApp, kAXWindowsAttribute) else { continue }
                let focused: AXUIElement? = axValue(axApp, kAXFocusedWindowAttribute)
                var used = Set<CGWindowID>()
                for window in windows {
                    let subrole: String = axValue(window, kAXSubroleAttribute) ?? ""
                    guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                    let rawTitle: String = axValue(window, kAXTitleAttribute) ?? ""
                    let minimized: Bool = axValue(window, kAXMinimizedAttribute) ?? false
                    var origin = CGPoint.zero
                    var size = CGSize.zero
                    if let value: AXValue = axValue(window, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &origin) }
                    if let value: AXValue = axValue(window, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
                    guard size.width > 40, size.height > 40 else { continue }
                    let bounds = CGRect(origin: origin, size: size)
                    let cgID = WindowMatcher.match(pid: app.processIdentifier, title: rawTitle, bounds: bounds,
                                                   preferredID: nil, candidates: candidates, excluding: used)
                    if let cgID { used.insert(cgID) }
                    // AX identity stays usable even when a minimized window has no CG entry.
                    let id = "\(app.processIdentifier):\(CFHash(window))"
                    let item = WindowItem(id: id, pid: app.processIdentifier, element: window,
                                          title: rawTitle.isEmpty ? (app.localizedName ?? "ウィンドウ") : rawTitle,
                                          appName: app.localizedName ?? "アプリ", icon: icon,
                                          windowID: cgID, minimized: minimized, bounds: bounds)
                    result.append(item)
                    if app.processIdentifier == frontPID, let focused, CFEqual(focused, window) { focusedID = id }
                }
            }
            DispatchQueue.main.async {
                self.refreshing = false
                completion(result, focusedID)
            }
        }
    }

    static func focus(_ item: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else { return }
        AXUIElementSetMessagingTimeout(item.element, 0.25)
        AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.activate(options: [])
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(item.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let axApp = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, item.element)
    }

    @MainActor
    static func thumbnails(for items: [WindowItem], receive: @escaping (String, NSImage?, ThumbnailState) -> Void) async {
        guard CGPreflightScreenCaptureAccess() else {
            for item in items { receive(item.id, nil, .permissionRequired) }
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let candidates = content.windows.filter { $0.windowLayer == 0 }.map {
                WindowCandidate(id: $0.windowID, pid: $0.owningApplication?.processID ?? -1,
                                title: $0.title ?? "", bounds: $0.frame)
            }
            var used = Set<UInt32>()
            for item in items {
                guard !Task.isCancelled else { return }
                if item.minimized { receive(item.id, nil, .minimized); continue }
                guard let matchedID = WindowMatcher.match(pid: item.pid, title: item.title, bounds: item.bounds,
                                                          preferredID: item.windowID, candidates: candidates, excluding: used),
                      let window = content.windows.first(where: { $0.windowID == matchedID }) else {
                    receive(item.id, nil, .unavailable)
                    continue
                }
                used.insert(matchedID)
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let ratio = max(0.2, window.frame.width / max(1, window.frame.height))
                let edge = PreviewImage.longestEdge
                config.width = ratio >= 1 ? edge : max(1, Int(Double(edge) * ratio))
                config.height = ratio >= 1 ? max(1, Int(Double(edge) / ratio)) : edge
                config.showsCursor = false
                config.captureResolution = .nominal
                config.ignoreShadowsSingleWindow = true
                do {
                    screenshotRequests += 1
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard !Task.isCancelled else { return }
                    autoreleasepool {
                        if let image = PreviewImage.make(cgImage) { receive(item.id, image, .ready) }
                        else { receive(item.id, nil, .unavailable) }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    receive(item.id, nil, .unavailable)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            for item in items { receive(item.id, nil, CGPreflightScreenCaptureAccess() ? .unavailable : .permissionRequired) }
        }
    }
}
