import AppKit
import SwiftUI

/// One card in the Dock preview panel: a window, its preview image, and whether
/// it can be closed.
struct DockPreviewCard: Identifiable {
    let window: WindowInfo
    let preview: WindowPreview?
    let canClose: Bool

    var id: WindowID { window.id }
}

/// Visual configuration for the Dock preview panel.
///
/// Scoped to this feature rather than reusing `SwitcherTheme`, whose three
/// branded variants are designed for a full-width switcher and are more assertive
/// than a small popup attached to the Dock should be. Follows the same storage
/// pattern as the other preferences.
enum DockPreviewTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    static let defaultsKey = "dockPreviewTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var primaryText: Color {
        self == .light ? Color.black.opacity(0.88) : Color.white.opacity(0.95)
    }

    var secondaryText: Color {
        self == .light ? Color.black.opacity(0.52) : Color.white.opacity(0.55)
    }

    var cardFill: Color {
        self == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.06)
    }

    var hoveredCardFill: Color {
        self == .light ? Color.black.opacity(0.09) : Color.white.opacity(0.13)
    }

    static var saved: DockPreviewTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let theme = DockPreviewTheme(rawValue: rawValue) else { return .system }
        return theme
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

@MainActor
final class DockPreviewViewModel: ObservableObject {
    @Published var applicationName = ""
    @Published var applicationIcon: NSImage?
    @Published var cards: [DockPreviewCard] = []
    @Published var theme = DockPreviewTheme.saved
    @Published var glassEnabled = SwitcherGlassPreference.saved
    @Published var layout = DockPreviewLayoutCalculator().calculateLayout(
        itemCount: 0,
        availableSize: CGSize(width: 800, height: 600),
        dockEdge: .bottom,
        displayScale: 2
    )

    var windowCountLabel: String {
        cards.count == 1 ? "1 window" : "\(cards.count) windows"
    }
}

/// The Dock preview popup content.
///
/// Deliberately restrained: native material, one accent per card, no permanent
/// borders, and no scale animation on hover. Keyboard focus is never taken, so
/// none of the controls are focusable.
struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewViewModel
    let onSelect: (WindowID) -> Void
    let onClose: (WindowID) -> Void
    let onHover: (WindowID, Bool) -> Void
    let onPointerEntered: () -> Void
    let onPointerExited: () -> Void
    let livePreviewCoordinator: LivePreviewCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: model.layout.panelSize.width, height: model.layout.panelSize.height)
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.white.opacity(colorSchemeContrast == .increased ? 0.30 : 0.12),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .preferredColorScheme(model.theme.colorScheme)
        .onHover { hovering in
            if hovering {
                onPointerEntered()
            } else {
                onPointerExited()
            }
        }
    }

    private var resolvedTheme: DockPreviewTheme {
        model.theme == .system ? (colorScheme == .dark ? .dark : .light) : model.theme
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = model.applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(model.applicationName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(resolvedTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(model.windowCountLabel)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(resolvedTheme.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, model.layout.contentInsets)
        .frame(height: model.layout.headerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.applicationName), \(model.windowCountLabel)")
    }

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: model.layout.requiresScrolling) {
            LazyVGrid(columns: gridColumns, spacing: model.layout.verticalSpacing) {
                ForEach(model.cards) { card in
                    DockPreviewCardView(
                        card: card,
                        previewSize: model.layout.previewSize,
                        itemSize: model.layout.itemSize,
                        theme: resolvedTheme,
                        livePreviewCoordinator: livePreviewCoordinator,
                        reduceMotion: reduceMotion,
                        onSelect: { onSelect(card.id) },
                        onClose: { onClose(card.id) },
                        onHover: { onHover(card.id, $0) }
                    )
                }
            }
            .padding(.horizontal, model.layout.contentInsets)
            .padding(.bottom, model.layout.contentInsets)
        }
        .frame(maxHeight: .infinity)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(model.layout.itemSize.width), spacing: model.layout.horizontalSpacing),
            count: max(1, model.layout.columns)
        )
    }

    @ViewBuilder
    private var panelBackground: some View {
        ZStack {
            if model.glassEnabled, !reduceTransparency {
                Color.black.opacity(0.18)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(0.97)
            }
        }
    }
}

private struct DockPreviewCardView: View {
    let card: DockPreviewCard
    let previewSize: CGSize
    let itemSize: CGSize
    let theme: DockPreviewTheme
    let livePreviewCoordinator: LivePreviewCoordinator
    let reduceMotion: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var window: WindowInfo { card.window }

    var body: some View {
        VStack(spacing: 0) {
            previewSurface
            caption
        }
        .frame(width: itemSize.width, height: itemSize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? theme.hoveredCardFill : theme.cardFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.primaryText.opacity(isHovered ? 0.22 : 0), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .onTapGesture(perform: onSelect)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Activates this window")
        .accessibilityAddTraits(.isButton)
    }

    private var previewSurface: some View {
        ZStack {
            if let preview = card.preview {
                Image(decorative: preview.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                    .id(preview.id)
                    .transition(.opacity)
            } else {
                placeholder
            }

            LiveWindowPreviewView(windowID: window.id, coordinator: livePreviewCoordinator)
                .id(window.id)

            stateIndicators
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .background(Color.black.opacity(theme == .light ? 0.06 : 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .topTrailing) { closeButton }
    }

    /// Shown until a valid frame arrives. The application icon, never an empty
    /// rectangle, so a card is always identifiable.
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.cardFill, theme.cardFill.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .opacity(0.9)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if card.canClose, isHovered {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(Color.black.opacity(theme == .light ? 0.35 : 0.55))
                    )
            }
            .buttonStyle(.plain)
            .padding(5)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityLabel("Close \(window.title) window")
            .help("Close window")
        }
    }

    @ViewBuilder
    private var stateIndicators: some View {
        if window.isMinimized || window.isFullscreen || window.isApplicationHidden {
            HStack(spacing: 4) {
                if window.isMinimized { symbol("minus.rectangle") }
                if window.isFullscreen { symbol("arrow.up.left.and.arrow.down.right") }
                if window.isApplicationHidden { symbol("eye.slash") }
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(3)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .accessibilityHidden(true)
    }

    private var caption: some View {
        Text(window.title)
            .font(.system(size: 11, weight: isHovered ? .medium : .regular))
            .foregroundStyle(isHovered ? theme.primaryText : theme.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
            .padding(.top, 5)
            .help(window.title)
    }

    private var accessibilityLabel: String {
        var parts = ["\(window.applicationName) — \(window.title)", "window preview"]
        if window.isMinimized { parts.append("minimized") }
        if window.isFullscreen { parts.append("full screen") }
        return parts.joined(separator: ", ")
    }
}
