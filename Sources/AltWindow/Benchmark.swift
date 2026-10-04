import AppKit
import ScreenCaptureKit
import Darwin

struct MemorySample: Codable {
    let phase: String
    let footprintBytes: UInt64
    let residentBytes: UInt64
    let thumbnailCount: Int
    let thumbnailPixelBytes: Int
}

extension AppDelegate {
    /// Explicit opt-in benchmark. No key injection, window activation, or stored pixels.
    func runBenchmark() {
        Task { @MainActor in
            var samples: [MemorySample] = []
            func sample(_ phase: String) {
                var info = task_vm_info_data_t()
                var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                    }
                }
                guard result == KERN_SUCCESS else { return }
                let bytes = self.thumbnailCache.values.values.reduce(0) { sum, image in
                    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return sum }
                    return sum + cg.bytesPerRow * cg.height
                }
                samples.append(MemorySample(phase: phase, footprintBytes: info.phys_footprint,
                                             residentBytes: info.resident_size,
                                             thumbnailCount: self.thumbnailCache.count, thumbnailPixelBytes: bytes))
            }
            func pause(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
            do {
                guard CGPreflightScreenCaptureAccess() else { throw NSError(domain: "ScreenCapturePermissionRequired", code: 1) }
                sample("cold")
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                let eligible = content.windows.filter {
                    $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 &&
                    $0.owningApplication?.bundleIdentifier == "com.google.Chrome"
                }
                let args = CommandLine.arguments
                let manifestPath = args.firstIndex(of: "--benchmark-manifest").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                var selected = Array(eligible.sorted { $0.windowID < $1.windowID }.prefix(4))
                if let manifestPath {
                    let manifestURL = URL(fileURLWithPath: manifestPath)
                    if FileManager.default.fileExists(atPath: manifestPath) {
                        let ids = try JSONDecoder().decode([UInt32].self, from: Data(contentsOf: manifestURL))
                        selected = ids.compactMap { id in eligible.first { $0.windowID == id } }
                        guard selected.count == ids.count else { throw NSError(domain: "BenchmarkWindowsChanged", code: 3) }
                    } else {
                        try JSONEncoder().encode(selected.map(\.windowID)).write(to: manifestURL)
                    }
                }
                let windows: [WindowItem] = selected.map { window in
                    WindowItem(id: "benchmark-\(window.windowID)", pid: window.owningApplication!.processID,
                               element: AXUIElementCreateApplication(window.owningApplication!.processID),
                               title: "Benchmark window", appName: "Chrome",
                               icon: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!,
                               windowID: window.windowID, minimized: false, bounds: window.frame)
                }
                guard !windows.isEmpty else { throw NSError(domain: "NoChromeWindows", code: 2) }
                self.cache = windows
                for iteration in 1...30 {
                    self.begin(windows, currentID: windows.first?.id, backwards: false)
                    let deadline = Date().addingTimeInterval(4)
                    while self.captureTask != nil && Date() < deadline { await pause(50) }
                    await pause(100)
                    if iteration == 1 { sample("first_open") }
                    self.finish(commit: false)
                    await pause(150)
                    if iteration % 10 == 0 { sample("closed_\(iteration)") }
                }
                await pause(3500)
                sample("idle_3s")
                await pause(12000)
                sample("idle_15s")
                struct Report: Codable {
                    let operatingSystem: String
                    let windows: Int
                    let iterations: Int
                    let screenshotRequests: Int
                    let samples: [MemorySample]
                }
                let report = Report(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                    windows: windows.count, iterations: 30, screenshotRequests: WindowCatalog.screenshotRequests, samples: samples)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("Benchmark failed: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }
}
