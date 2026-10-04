import Foundation

enum ThumbnailSize: String, CaseIterable {
    case small, medium, large
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "thumbnailSize") ?? "") ?? .medium }
    var width: CGFloat {
        switch self { case .small: return 220; case .medium: return 300; case .large: return 380 }
    }
    var label: String {
        switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" }
    }
}
