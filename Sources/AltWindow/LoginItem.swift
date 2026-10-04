import AppKit
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openSettings()
}

@MainActor
final class SystemLoginItem: LoginItemManaging {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var isChanging = false
    @Published private(set) var errorMessage: String?
    private let service: LoginItemManaging

    init(service: LoginItemManaging) {
        self.service = service
        refresh()
    }
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var detail: String {
        if let errorMessage { return errorMessage }
        switch status {
        case .enabled: return "オン：次回のログインから自動起動します。"
        case .requiresApproval: return "macOSのログイン項目でAltWindowを許可してください。"
        case .notFound: return "ログイン項目は未登録です。オンにして登録してください。"
        case .notRegistered: return "オフ：ログイン時には起動しません。"
        @unknown default: return "ログイン項目の状態を確認できません。"
        }
    }
    func refresh() {
        let actual = service.status
        if actual != status { status = actual }
    }
    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = nil
        defer { refresh(); isChanging = false }
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try await service.unregister()
            }
        } catch {
            errorMessage = "変更できませんでした（\((error as NSError).code)）。ログイン項目の設定を確認して再試行してください。"
        }
    }
    func openSettings() { service.openSettings() }
}

enum StartupPresentation {
    static func shouldShowSettings(missingPermissions: Bool, loginItemRegistered: Bool,
                                   backgroundLaunch: Bool, explicitlyRequested: Bool) -> Bool {
        explicitlyRequested || (missingPermissions && !loginItemRegistered && !backgroundLaunch)
    }

    static func isBackgroundLaunch(event: NSAppleEventDescriptor?, arguments: [String]) -> Bool {
        if arguments.contains("--background") { return true }
        let launchReason = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return launchReason == OSType(keyAELaunchedAsLogInItem) || launchReason == OSType(keyAELaunchedAsServiceItem)
    }
}
