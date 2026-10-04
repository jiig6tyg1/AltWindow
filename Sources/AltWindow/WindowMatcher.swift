import Foundation

struct WindowCandidate {
    let id: UInt32
    let pid: Int32
    let title: String
    let bounds: CGRect
}

enum WindowMatcher {
    /// Match ownership first. Titles can differ between AX and ScreenCaptureKit
    /// (Chrome appends its app name); unique geometry is stronger evidence.
    static func match(pid: Int32, title: String, bounds: CGRect, preferredID: UInt32?,
                      candidates: [WindowCandidate], excluding: Set<UInt32> = []) -> UInt32? {
        let owned = candidates.filter { $0.pid == pid && !excluding.contains($0.id) }
        if let preferredID, owned.contains(where: { $0.id == preferredID }) { return preferredID }
        let geometric = owned.filter {
            abs($0.bounds.minX - bounds.minX) < 8 && abs($0.bounds.minY - bounds.minY) < 8 &&
            abs($0.bounds.width - bounds.width) < 8 && abs($0.bounds.height - bounds.height) < 8
        }
        if geometric.count == 1 { return geometric[0].id }
        let normalized = normalize(title)
        guard !normalized.isEmpty else { return nil }
        let titled = (geometric.isEmpty ? owned : geometric).filter { normalize($0.title) == normalized }
        return titled.count == 1 ? titled[0].id : nil
    }

    private static func normalize(_ title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - Google Chrome", " – Google Chrome", " — Google Chrome", " - Chromium"] {
            if value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        }
        return value
    }
}
