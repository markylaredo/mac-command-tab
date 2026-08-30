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

    var panelHeight: CGFloat {
        switch self {
        case .circle: 500
        case .tile: 340
        case .carousel: 244
        }
    }

    var cardWidth: CGFloat {
        switch self {
        case .circle: 58
        case .tile: 210
        case .carousel: 246
        }
    }

    var cardSpacing: CGFloat {
        switch self {
        case .circle: 10
        case .tile: 10
        case .carousel: 10
        }
    }

    var navigationLayout: SwitcherNavigationLayout {
        self == .tile ? .tileGrid : .linear
    }

    static var saved: SwitcherPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey) else { return .circle }
        if let preset = SwitcherPreset(rawValue: rawValue) { return preset }

        // Preserve choices written by the earlier visual-theme implementation.
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
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.preset {
            case .circle:
                circleLayout
            case .tile:
                tileLayout
            case .carousel:
                carouselLayout
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.preset)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.theme)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.glassEnabled)
    }

    private var circleLayout: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 + 6)
            let radiusX = min(geometry.size.width * 0.39, 258)
            let radiusY = min(geometry.size.height * 0.35, 172)

            ZStack {
                panelBackground

                Ellipse()
                    .stroke(model.theme.primaryText.opacity(0.075), style: StrokeStyle(lineWidth: 1, dash: [5, 7]))
                    .frame(width: radiusX * 2, height: radiusY * 2)
                    .position(center)

                Ellipse()
                    .stroke(model.theme.secondaryAccent.opacity(0.10), lineWidth: 18)
                    .frame(width: radiusX * 2, height: radiusY * 2)
                    .blur(radius: 12)
                    .position(center)

                if let selectedWindow {
                    CircleSelectionCard(
                        window: selectedWindow,
                        preview: model.previews[selectedWindow.id],
                        theme: model.theme,
                        selectionEffect: model.selectionEffect
                    )
                    .id(selectedWindow.id)
                    .position(center)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(2)
                }

                ForEach(circleEntries) { entry in
                    let angle = circleAngle(for: entry.offset, visibleCount: circleEntries.count)
                    CircleWindowNode(
                        window: entry.window,
                        index: entry.index,
                        isSelected: entry.offset == 0,
                        theme: model.theme
                    )
                    .position(
                        x: center.x + cos(angle) * radiusX,
                        y: center.y + sin(angle) * radiusY
                    )
                    .zIndex(entry.offset == 0 ? 4 : 3)
                }

                circleHeader
                    .frame(maxHeight: .infinity, alignment: .top)

                HStack(spacing: 14) {
                    shortcutHint("TAB", label: "ROTATE")
                    shortcutHint("⇧ TAB", label: "REVERSE")
                    shortcutHint("⌥", label: "SELECT")
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: model.selectedIndex)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(model.theme.secondaryAccent.opacity(0.30), lineWidth: 1)
        }
    }

    private var tileLayout: some View {
        VStack(spacing: 0) {
            layoutHeader(title: "TILE GRID", symbol: "square.grid.2x2", accent: model.theme.accent)
            Rectangle().fill(model.theme.primaryText.opacity(0.08)).frame(height: 1)
            tileGrid
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(model.theme.secondaryAccent.opacity(0.28), lineWidth: 1)
        }
    }

    private var carouselLayout: some View {
        VStack(spacing: 0) {
            layoutHeader(title: "WINDOW CAROUSEL", symbol: "scope", accent: model.theme.accent)
            Rectangle().fill(model.theme.primaryText.opacity(0.09)).frame(height: 1)
            carouselStrip
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
        }
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(model.theme.secondaryAccent.opacity(0.30), lineWidth: 1)
        }
    }

    private var tileGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.fixed(132)), GridItem(.fixed(132))],
                    spacing: model.preset.cardSpacing
                ) {
                    ForEach(tileDisplayIndices, id: \.self) { index in
                        let window = model.windows[index]
                        WindowCardView(
                            window: window,
                            preview: model.previews[window.id],
                            isSelected: index == model.selectedIndex,
                            index: index,
                            preset: .tile,
                            theme: model.theme,
                            selectionEffect: model.selectionEffect
                        )
                        .id(window.id)
                    }
                }
            }
            .onChange(of: model.selectedIndex) { _, newIndex in
                scrollToSelection(newIndex, using: proxy)
            }
        }
    }

    private var carouselStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: model.preset.cardSpacing) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        WindowCardView(
                            window: window,
                            preview: model.previews[window.id],
                            isSelected: index == model.selectedIndex,
                            index: index,
                            preset: .carousel,
                            theme: model.theme,
                            selectionEffect: model.selectionEffect
                        )
                        .id(window.id)
                    }
                }
            }
            .onChange(of: model.selectedIndex) { _, newIndex in
                scrollToSelection(newIndex, using: proxy)
            }
        }
    }

    private var circleHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 13, weight: .bold))
            Text("WINDOW ORBIT")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
            Text(selectionCounter)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(model.theme.secondaryText)
            Spacer()
            Text(selectedWindow?.applicationName.uppercased() ?? "")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(model.theme.secondaryText.opacity(0.78))
        }
        .foregroundStyle(model.theme.accent)
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    private func layoutHeader(title: String, symbol: String, accent: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
            Text(selectionCounter)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(model.theme.secondaryText)
            Spacer()
            shortcutHint("TAB", label: "CYCLE")
            shortcutHint("⌥", label: "SELECT")
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 17)
        .frame(height: 42)
    }

    @ViewBuilder
    private var panelBackground: some View {
        ZStack {
            if model.glassEnabled {
                Rectangle().fill(.ultraThinMaterial)
                glassTint
                LinearGradient(
                    colors: [Color.white.opacity(0.12), .clear, Color.black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                opaqueThemeBackground
            }

            LinearGradient(
                colors: [model.theme.primaryText.opacity(model.glassEnabled ? 0.10 : 0.04), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.screen)
        }
    }

    @ViewBuilder
    private var glassTint: some View {
        switch model.theme {
        case .game:
            Color(red: 0.025, green: 0.055, blue: 0.055).opacity(0.58)
            RadialGradient(
                colors: [model.theme.secondaryAccent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 430
            )
        case .classic:
            Color.primary.opacity(0.035)
            LinearGradient(
                colors: [Color.white.opacity(0.09), model.theme.accent.opacity(0.045)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .modern:
            Color(red: 0.035, green: 0.025, blue: 0.11).opacity(0.62)
            RadialGradient(
                colors: [model.theme.secondaryAccent.opacity(0.32), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [model.theme.accent.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 360
            )
        }
    }

    @ViewBuilder
    private var opaqueThemeBackground: some View {
        switch model.theme {
        case .game:
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.040, blue: 0.043),
                    Color(red: 0.060, green: 0.078, blue: 0.080)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .classic:
            Color(nsColor: .windowBackgroundColor)
        case .modern:
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.022, blue: 0.075),
                    Color(red: 0.065, green: 0.042, blue: 0.135)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var selectedWindow: WindowInfo? {
        guard model.windows.indices.contains(model.selectedIndex) else { return nil }
        return model.windows[model.selectedIndex]
    }

    private var circleEntries: [CircleEntry] {
        let count = model.windows.count
        guard count > 0 else { return [] }
        let visibleCount = min(count, 10)
        let startOffset = -(visibleCount / 2)

        return (0..<visibleCount).map { position in
            let offset = startOffset + position
            let index = (model.selectedIndex + offset + count) % count
            return CircleEntry(index: index, offset: offset, window: model.windows[index])
        }
    }

    private var tileDisplayIndices: [Int] {
        let count = model.windows.count
        guard count > 0 else { return [] }
        let columns = (count + 1) / 2

        return (0..<columns).flatMap { column in
            [column, column + columns].filter { $0 < count }
        }
    }

    private func circleAngle(for offset: Int, visibleCount: Int) -> Double {
        guard visibleCount > 0 else { return -.pi / 2 }
        return -.pi / 2 + Double(offset) * (2 * .pi / Double(visibleCount))
    }

    private var selectionCounter: String {
        guard !model.windows.isEmpty else { return "00 / 00" }
        return String(format: "%02d / %02d", model.selectedIndex + 1, model.windows.count)
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(model.theme.primaryText.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(model.theme.secondaryText)
    }

    private func scrollToSelection(_ index: Int, using proxy: ScrollViewProxy) {
        guard model.windows.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) {
            proxy.scrollTo(model.windows[index].id, anchor: .center)
        }
    }

}

private struct CircleEntry: Identifiable {
    let index: Int
    let offset: Int
    let window: WindowInfo

    var id: WindowID { window.id }
}
