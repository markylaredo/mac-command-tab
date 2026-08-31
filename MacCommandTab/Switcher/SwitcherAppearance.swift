import Foundation

enum SwitcherAppearance: String, CaseIterable, Identifiable, Sendable {
    case thumbnails
    case appIcons
    case windowTitles

    static let defaultsKey = "switcherAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thumbnails: "Window Tiles"
        case .appIcons: "App Icons"
        case .windowTitles: "Window Titles"
        }
    }

    var subtitle: String {
        switch self {
        case .thumbnails: "Live window previews with titles"
        case .appIcons: "Large icons for every individual window"
        case .windowTitles: "Compact list for many windows"
        }
    }

    var headerTitle: String { title.uppercased() }

    static var saved: SwitcherAppearance {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let appearance = SwitcherAppearance(rawValue: rawValue) else {
            return .thumbnails
        }
        return appearance
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
