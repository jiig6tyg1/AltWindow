import AppKit
import ApplicationServices
import SwiftUI
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let catalog = WindowCatalog()
    let switcher = SwitcherModel()
    let permissions = PermissionModel()
    @MainActor lazy var loginItem = LoginItemController(service: SystemLoginItem())
    var selection = Selection()
    var cache: [WindowItem] = []
    var recency: [String: TimeInterval] = [:]
    var focusedID: String?
    var panel: NSPanel?
    var settings: NSWindow?
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var eventSource: CFRunLoopSource?
    var timer: Timer?
    var captureTask: Task<Void, Never>?
    var demo = false
    var lastAX = false
    var observer: NSObjectProtocol?
    var demoMonitor: Any?
    var clickMode = false
    var captureGeneration = 0
    var thumbnailCache = CostCache<NSImage>(byteLimit: 8 * 1024 * 1024, countLimit: 24)
    var pendingCaptures: [WindowItem] = []
    var inFlightCaptureIDs = Set<String>()
    var idleCleanup: DispatchWorkItem?
    var pressureSource: DispatchSourceMemoryPressure?
    var hotkeyRouter = HotkeyRouter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--diagnose") { runDiagnostics(); return }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"), let icon = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = icon
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "AltWindow")
        let menu = NSMenu()
        for (title, action, key) in [("ウィンドウを表示", #selector(showWindows), ""),
                                     ("設定…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "AltWindowを終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        permissions.enableAX = { [weak self] in self?.requestAX() }
        permissions.enableKeyboard = { [weak self] in
            CGRequestListenEventAccess()
            self?.openPrivacy("Privacy_ListenEvent")
        }
        permissions.enableCapture = { [weak self] in
            if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            self?.openPrivacy("Privacy_ScreenCapture")
        }
        permissions.preview = { [weak self] in self?.showDemo() }
        switcher.choose = { [weak self] index in
            guard index >= 0 else { self?.finish(commit: false); return }
            self?.selection.select(index)
            self?.finish(commit: true)
        }
        switcher.requestPreview = { [weak self] id in self?.requestPreview(id) }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in self?.releasePreviews() }
        pressure.resume()
        pressureSource = pressure
        if CommandLine.arguments.contains("--benchmark") { runBenchmark(); return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.4
        tick()
        let backgroundLaunch = StartupPresentation.isBackgroundLaunch(
            event: NSAppleEventManager.shared().currentAppleEvent, arguments: CommandLine.arguments)
        if StartupPresentation.shouldShowSettings(missingPermissions: !permissions.accessibility || !permissions.keyboard,
                                                  loginItemRegistered: loginItem.isRegistered,
                                                  backgroundLaunch: backgroundLaunch,
                                                  explicitlyRequested: CommandLine.arguments.contains("--settings")) {
            showSettings()
        }
        if CommandLine.arguments.contains("--demo") { showDemo() }
        if CommandLine.arguments.contains("--windows") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.showWindows() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func tick() {
        if settings?.isVisible == true { MainActor.assumeIsolated { loginItem.refresh() } }
        let trusted = AXIsProcessTrusted()
        if permissions.accessibility != trusted { permissions.accessibility = trusted }
        let captureAllowed = CGPreflightScreenCaptureAccess()
        if permissions.capture && !captureAllowed {
            releasePreviews()
        }
        if permissions.capture != captureAllowed { permissions.capture = captureAllowed }
        if trusted, eventTap == nil { installTap() }
        if !trusted, lastAX { finish(commit: false); removeTap(); cache = []; releasePreviews() }
        lastAX = trusted
        // A tap can exist while TCC rejects input monitoring after a signing change.
        let keyboardReady = CGPreflightListenEventAccess() && (eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
        if permissions.keyboard != keyboardReady { permissions.keyboard = keyboardReady }
        refresh()
    }

    func refresh() {
        guard !selection.isOpen else { return }
        catalog.refresh { [weak self] windows, focused in
            guard let self, !self.selection.isOpen else { return }
            if let focused, self.focusedID != focused {
                self.recency[focused] = Date.timeIntervalSinceReferenceDate
            }
            self.focusedID = focused
            self.cache = windows.sorted {
                let a = self.recency[$0.id] ?? 0, b = self.recency[$1.id] ?? 0
                if a != b { return a > b }
                return ($0.appName, $0.title, $0.id) < ($1.appName, $1.title, $1.id)
            }
            let ids = Set(windows.map(\.id))
            self.recency = self.recency.filter { ids.contains($0.key) }
            self.thumbnailCache.retain(keys: ids)
            self.switcher.thumbnailStates = self.switcher.thumbnailStates.filter { ids.contains($0.key) }
        }
    }

    func startCapture(_ windows: [WindowItem]) {
        guard selection.isOpen, !demo else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for window in windows where !thumbnailCache.isFresh(window.id, now: now, maxAge: 3) {
            if inFlightCaptureIDs.contains(window.id), captureTask?.isCancelled != true { continue }
            if !pendingCaptures.contains(where: { $0.id == window.id }) { pendingCaptures.append(window) }
        }
        // New on-screen requests take priority. Bound pending work even on fast scroll.
        pendingCaptures = Array(pendingCaptures.suffix(24))
        drainCaptures()
    }

    func requestPreview(_ id: String) {
        guard selection.isOpen, !demo, let item = switcher.windows.first(where: { $0.id == id }) else { return }
        startCapture([item])
    }

    func drainCaptures() {
        pendingCaptures.removeAll { thumbnailCache.isFresh($0.id, now: ProcessInfo.processInfo.systemUptime, maxAge: 3) }
        guard captureTask == nil, selection.isOpen, !pendingCaptures.isEmpty else { return }
        let generation = captureGeneration
        let windows = Array(pendingCaptures.prefix(12))
        pendingCaptures.removeFirst(windows.count)
        inFlightCaptureIDs = Set(windows.map(\.id))
        captureTask = Task { @MainActor [weak self] in
            await WindowCatalog.thumbnails(for: windows) { id, image, state in
                guard let self, generation == self.captureGeneration, self.selection.isOpen else { return }
                self.switcher.thumbnailStates[id] = state
                if let image {
                    self.thumbnailCache.insert(image, for: id, cost: PreviewImage.cost(image), now: ProcessInfo.processInfo.systemUptime)
                    self.switcher.thumbnails = self.thumbnailCache.values
                }
            }
            guard let self else { return }
            self.captureTask = nil
            self.inFlightCaptureIDs.removeAll()
            // Wait for the cancelled API request to actually finish before starting another.
            self.drainCaptures()
        }
    }

    func releasePreviews() {
        captureGeneration += 1
        captureTask?.cancel()
        pendingCaptures.removeAll()
        thumbnailCache.removeAll()
        switcher.thumbnails = [:]
        switcher.thumbnailStates = [:]
        if !selection.isOpen {
            switcher.windows = []
            panel?.contentView = nil
            panel?.close()
            panel = nil
            // The view teardown releases many small allocations. Once AppKit's
            // autorelease cycle has drained, return unused allocator pages too.
            // Run only after idle teardown, never in a key event or an open panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !self.selection.isOpen, self.thumbnailCache.count == 0 else { return }
                DispatchQueue.global(qos: .utility).async { _ = malloc_zone_pressure_relief(nil, 0) }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settings else { return }
        settings = nil
        window.contentView = nil
    }

    @objc func showWindows() {
        finish(commit: false)
        guard !cache.isEmpty else { showSettings(); return }
        demo = false
        clickMode = true
        begin(cache, currentID: focusedID, backwards: false)
    }

    func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                owner.hotkeyRouter.reset()
                DispatchQueue.main.async { owner.finish(commit: false) }
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let option = flags.contains(.maskAlternate)
            let consume: Bool
            if type == .flagsChanged {
                owner.hotkeyRouter.flagsChanged(option: option)
                consume = false
            } else {
                consume = owner.hotkeyRouter.keyDown(key, option: option, command: flags.contains(.maskCommand),
                                                     control: flags.contains(.maskControl), canOpen: !owner.cache.isEmpty,
                                                     panelOpen: owner.selection.isOpen)
            }
            if consume || type == .flagsChanged {
                DispatchQueue.main.async { _ = owner.handle(type: type, key: key, flags: flags) }
            }
            return consume ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let eventTap {
            eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func handle(type: CGEventType, key: Int64, flags: CGEventFlags) -> Bool {
        let option = flags.contains(.maskAlternate)
        if type == .flagsChanged {
            if selection.isOpen, !demo, !clickMode, !option { finish(commit: true) }
            return false
        }
        if key == 48, option, !flags.contains(.maskCommand), !flags.contains(.maskControl) {
            if selection.isOpen {
                selection.step(flags.contains(.maskShift) ? -1 : 1)
                switcher.selected = selection.index
            } else if !cache.isEmpty {
                demo = false
                clickMode = false
                let current = currentWindowID()
                let ordered = cache.sorted { $0.id == current && $1.id != current }
                begin(ordered, currentID: current, backwards: flags.contains(.maskShift))
            }
            return !cache.isEmpty || selection.isOpen
        }
        guard selection.isOpen else { return false }
        switch key {
        case 53: finish(commit: false)
        case 36, 76: finish(commit: true)
        case 123: selection.step(-1)
        case 124: selection.step(1)
        case 125: selection.step(min(switcher.columns, selection.ids.count))
        case 126: selection.step(-min(switcher.columns, selection.ids.count))
        default: return false
        }
        switcher.selected = selection.index
        return true
    }

    // Read focus at the start of the gesture, not from the two-second catalog snapshot.
    func currentWindowID() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.03)
        if let window: AXUIElement = axValue(axApp, kAXFocusedWindowAttribute),
           let item = cache.first(where: { $0.pid == app.processIdentifier && CFEqual($0.element, window) }) {
            return item.id
        }
        if let focusedID, cache.contains(where: { $0.pid == app.processIdentifier && $0.id == focusedID }) {
            return focusedID
        }
        return cache.first(where: { $0.pid == app.processIdentifier })?.id
    }

    func begin(_ windows: [WindowItem], currentID: String?, backwards: Bool) {
        idleCleanup?.cancel()
        idleCleanup = nil
        selection.begin(ids: windows.map(\.id), currentID: currentID, backwards: backwards)
        guard selection.isOpen else { return }
        switcher.windows = windows
        switcher.selected = selection.index
        let now = ProcessInfo.processInfo.systemUptime
        for window in windows { _ = thumbnailCache.value(for: window.id, now: now, maxAge: 15) }
        switcher.thumbnails = thumbnailCache.values
        if demo { for window in windows { switcher.thumbnailStates[window.id] = .demo } }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            finish(commit: false)
            return
        }
        let preferredWidth = ThumbnailSize.current.width
        let columns = max(1, min(4, windows.count, Int((screen.visibleFrame.width - 80) / (preferredWidth + 12))))
        let width = min(CGFloat(columns) * (preferredWidth + 12) + 20, screen.visibleFrame.width - 60)
        switcher.columns = columns
        switcher.previewHeight = max(80, ((width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)) * 0.56)
        let rows = min(3, (windows.count + columns - 1) / columns)
        let height = min(CGFloat(rows) * (switcher.previewHeight + 56) + 32, screen.visibleFrame.height - 60)
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - height / 2, width: width, height: height)
        if panel == nil {
            panel = SwitcherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel?.level = .statusBar
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel?.isOpaque = false
            panel?.backgroundColor = .clear
            panel?.hasShadow = true
            panel?.hidesOnDeactivate = false
            panel?.isReleasedWhenClosed = false
            panel?.title = "AltWindow — ウィンドウ"
            panel?.contentView = nil
        }
        panel?.setFrame(frame, display: true)
        panel?.contentView = glassHost(SwitcherView(model: switcher), radius: 16, size: frame.size)
        if clickMode || demo { panel?.makeKeyAndOrderFront(nil) }
        else { panel?.orderFrontRegardless() }
        if !demo {
            let selectedID = selection.selectedID
            startCapture(Array(windows.sorted { $0.id == selectedID && $1.id != selectedID }.prefix(12)))
        }
    }

    func finish(commit: Bool) {
        guard selection.isOpen else { return }
        let id = selection.finish(commit: commit)
        let item = switcher.windows.first { $0.id == id }
        panel?.orderOut(nil)
        captureGeneration += 1
        captureTask?.cancel()
        pendingCaptures.removeAll()
        switcher.thumbnails = [:]
        switcher.windows = []
        switcher.thumbnailStates = [:]
        idleCleanup?.cancel()
        let cleanup = DispatchWorkItem { [weak self] in self?.releasePreviews() }
        idleCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: cleanup)
        if let item, !demo {
            recency[item.id] = Date.timeIntervalSinceReferenceDate
            // Perform AX IPC outside the event tap callback.
            WindowCatalog.focus(item)
        }
        demo = false
        clickMode = false
        if let demoMonitor { NSEvent.removeMonitor(demoMonitor); self.demoMonitor = nil }
    }

    @objc func showSettings() {
        MainActor.assumeIsolated { showSettingsOnMainActor() }
    }

    @MainActor private func showSettingsOnMainActor() {
        loginItem.refresh()
        finish(commit: false)
        if settings == nil {
            let host = glassHost(SettingsView(model: permissions, loginItem: loginItem))
            var size = host.frame.size
            size.height += 32
            settings = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            settings?.title = "AltWindow"
            settings?.delegate = self
            settings?.titlebarAppearsTransparent = true
            settings?.titleVisibility = .hidden
            settings?.isOpaque = false
            settings?.backgroundColor = .clear
            settings?.contentView = host
            settings?.setContentSize(size)
            settings?.isReleasedWhenClosed = false
            settings?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    @objc func showDemo() {
        finish(commit: false)
        demo = true
        let specs = [("Safari", "次のアイデアを探そう", "safari"), ("Finder", "プロジェクト", "folder.fill"), ("メモ", "今日のやること", "note.text"), ("ターミナル", "~/Projects", "terminal.fill")]
        let windows = specs.enumerated().map { index, spec in
            WindowItem(id: "demo-\(index)", pid: getpid(), element: AXUIElementCreateApplication(getpid()), title: spec.1, appName: spec.0,
                       icon: NSImage(systemSymbolName: spec.2, accessibilityDescription: spec.0) ?? NSImage(), windowID: nil, minimized: false)
        }
        begin(windows, currentID: "demo-0", backwards: false)
        // Also usable before global keyboard permission is granted.
        demoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.demo else { return event }
            if event.keyCode == 53 || event.keyCode == 36 { self.finish(commit: false); return nil }
            if event.keyCode == 48 || event.keyCode == 124 { self.selection.step(1); self.switcher.selected = self.selection.index; return nil }
            if event.keyCode == 123 { self.selection.step(-1); self.switcher.selected = self.selection.index; return nil }
            return event
        }
    }

    func requestAX() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }
    func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
    func removeTap() {
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        eventSource = nil
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        idleCleanup?.cancel()
        pressureSource?.cancel()
        captureTask?.cancel()
        removeTap()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
