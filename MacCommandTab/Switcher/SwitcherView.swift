import SwiftUI

enum SwitcherPreset: String, CaseIterable, Identifiable, Sendable {
    case circle
    case tile
    case carousel

    static let defaultsKey = "switcherPreset"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: "Circle"
        case .tile: "Tile Grid"
        case .carousel: "Carousel"
        }
    }

    var subtitle: String {
        switch self {
        case .circle: "Rotating window orbit"
        case .tile: "Two-row preview grid"
        case .carousel: "Tactical horizontal cards"
        }
    }

    var navigationLayout: SwitcherNavigationLayout {
        self == .tile ? .tileGrid : .linear
    }

    static var saved: SwitcherPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey) else { return .circle }
        if let preset = SwitcherPreset(rawValue: rawValue) { return preset }

        switch rawValue {
        case "tactical": return .carousel
        case "compact": return .tile
        default: return .circle
        }
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

enum SwitcherTheme: String, CaseIterable, Identifiable, Sendable {
    case game
    case classic
    case modern

    static let defaultsKey = "switcherTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .game: "Game"
        case .classic: "Classic"
        case .modern: "Modern"
        }
    }

    var subtitle: String {
        switch self {
        case .game: "Tactical HUD and targeting corners"
        case .classic: "Native macOS material and focus ring"
        case .modern: "Midnight glass with cyan-violet glow"
        }
    }

    var accent: Color {
        switch self {
        case .game: Color(red: 0.94, green: 0.69, blue: 0.25)
        case .classic: .accentColor
        case .modern: Color(red: 0.33, green: 0.85, blue: 1.0)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .game: Color(red: 0.35, green: 0.88, blue: 0.70)
        case .classic: Color.primary.opacity(0.34)
        case .modern: Color(red: 0.46, green: 0.34, blue: 1.0)
        }
    }

    var primaryText: Color {
        self == .classic ? .primary : Color.white.opacity(0.95)
    }

    var secondaryText: Color {
        self == .classic ? .secondary : Color.white.opacity(0.50)
    }

    var cardFill: Color {
        switch self {
        case .game: Color.black.opacity(0.24)
        case .classic: Color.primary.opacity(0.045)
        case .modern: Color(red: 0.10, green: 0.11, blue: 0.24).opacity(0.76)
        }
    }

    var selectedCardFill: Color {
        switch self {
        case .game: Color(red: 0.12, green: 0.17, blue: 0.18)
        case .classic: Color.accentColor.opacity(0.13)
        case .modern: Color(red: 0.16, green: 0.14, blue: 0.32).opacity(0.94)
        }
    }

    static var saved: SwitcherTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let theme = SwitcherTheme(rawValue: rawValue) else { return .game }
        return theme
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

enum SwitcherSelectionEffect: String, CaseIterable, Identifiable, Sendable {
    case focusLift
    case neonSweep
    case emberBurn
    case none

    static let defaultsKey = "switcherSelectionEffect"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusLift: "Focus Lift"
        case .neonSweep: "Neon Sweep"
        case .emberBurn: "Ember Burn"
        case .none: "None"
        }
    }

    var subtitle: String {
        switch self {
        case .focusLift: "Spring lift with a clean expanding focus ring"
        case .neonSweep: "A luminous trace travels around the selected item"
        case .emberBurn: "A hot edge sheds rising sparks"
        case .none: "Keep only the selected border"
        }
    }

    static var saved: SwitcherSelectionEffect {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let effect = SwitcherSelectionEffect(rawValue: rawValue) else { return .focusLift }
        return effect
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

enum SwitcherGlassPreference {
    static let defaultsKey = "switcherGlassEnabled"

    static var saved: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    static func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex = 0
    @Published var previews: [WindowID: WindowPreview] = [:]
    @Published var preset = SwitcherPreset.saved
    @Published var theme = SwitcherTheme.saved
    @Published var glassEnabled = SwitcherGlassPreference.saved
    @Published var selectionEffect = SwitcherSelectionEffect.saved
    @Published var appearance = SwitcherAppearance.saved
    @Published var layout = SwitcherLayout.empty
    @Published var searchQuery = ""
}
