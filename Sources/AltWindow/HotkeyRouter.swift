/// Runs synchronously in the event tap. Rendering and AX work must never run here.
struct HotkeyRouter {
    private(set) var gestureActive = false

    mutating func keyDown(_ key: Int64, option: Bool, command: Bool, control: Bool,
                          canOpen: Bool, panelOpen: Bool) -> Bool {
        if key == 48, option, !command, !control, canOpen || panelOpen || gestureActive {
            gestureActive = true
            return true
        }
        guard gestureActive || panelOpen else { return false }
        switch key {
        case 53, 36, 76:
            gestureActive = false
            return true
        case 123...126: return true
        default: return false
        }
    }
    mutating func flagsChanged(option: Bool) { if !option { gestureActive = false } }
    mutating func reset() { gestureActive = false }
}
