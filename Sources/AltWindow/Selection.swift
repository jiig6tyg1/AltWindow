import Foundation

/// Selection is frozen to one snapshot for the duration of a keyboard gesture.
struct Selection {
    private(set) var ids: [String] = []
    private(set) var index = 0
    private(set) var isOpen = false
    var selectedID: String? { ids.indices.contains(index) ? ids[index] : nil }

    mutating func begin(ids: [String], currentID: String?, backwards: Bool) {
        self.ids = ids
        isOpen = !ids.isEmpty
        if let currentID, let currentIndex = ids.firstIndex(of: currentID) {
            index = currentIndex
            step(backwards ? -1 : 1)
        } else {
            index = backwards ? max(0, ids.count - 1) : 0
        }
    }
    mutating func step(_ delta: Int) {
        guard isOpen, !ids.isEmpty else { return }
        index = ((index + delta) % ids.count + ids.count) % ids.count
    }
    mutating func select(_ index: Int) {
        guard isOpen, ids.indices.contains(index) else { return }
        self.index = index
    }
    mutating func finish(commit: Bool) -> String? {
        let result = commit ? selectedID : nil
        isOpen = false
        ids = []
        index = 0
        return result
    }
}
