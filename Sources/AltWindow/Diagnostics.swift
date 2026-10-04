import AppKit
import ApplicationServices
import ScreenCaptureKit

extension AppDelegate {
    /// Counts only: never writes window titles, browsing data, or screenshot pixels.
    func runDiagnostics() {
        let accessibility = AXIsProcessTrusted()
        let screenCapture = CGPreflightScreenCaptureAccess()
        func report(_ fields: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            report(["accessibility": accessibility, "screenCapture": screenCapture, "timeout": true])
        }
        guard accessibility else {
            guard screenCapture else {
                report(["accessibility": false, "screenCapture": false])
                return
            }
            Task { @MainActor in
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                    let chrome = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.google.Chrome" && $0.windowLayer == 0 }
                    let items = chrome.map { window in
                        WindowItem(id: "diagnostic-\(window.windowID)", pid: window.owningApplication!.processID,
                                   element: AXUIElementCreateApplication(window.owningApplication!.processID),
                                   title: window.title ?? "", appName: "Chrome", icon: NSImage(),
                                   windowID: nil, minimized: false, bounds: window.frame)
                    }
                    var captures = 0
                    await WindowCatalog.thumbnails(for: items) { _, image, _ in if image != nil { captures += 1 } }
                    report(["accessibility": false, "screenCapture": true, "source": "ScreenCaptureKit",
                            "chromeWindows": chrome.count, "chromeThumbnails": captures])
                } catch {
                    report(["accessibility": false, "screenCapture": screenCapture, "captureError": (error as NSError).code])
                }
            }
            return
        }
        catalog.refresh { windows, _ in
            let chrome = windows.filter {
                NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier == "com.google.Chrome"
            }
            Task { @MainActor in
                var captures = 0
                var unavailable = 0
                await WindowCatalog.thumbnails(for: chrome) { _, image, state in
                    if image != nil { captures += 1 }
                    if state == .unavailable { unavailable += 1 }
                }
                report(["accessibility": accessibility, "screenCapture": screenCapture,
                        "windowCount": windows.count, "chromeWindows": chrome.count,
                        "chromeMatchedCGWindows": chrome.filter { $0.windowID != nil }.count,
                        "chromeThumbnails": captures, "chromeUnavailable": unavailable])
            }
        }
    }
}
