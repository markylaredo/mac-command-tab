import SwiftUI

struct AdaptiveSwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    let livePreviewCoordinator: LivePreviewCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(model.theme.primaryText.opacity(0.07))
                .frame(height: 1)
            content
        }
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(model.theme.secondaryAccent.opacity(0.30), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.appearance)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: model.searchQuery.isEmpty ? appearanceSymbol : "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
            Text(model.searchQuery.isEmpty ? model.appearance.headerTitle : "SEARCH")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.0)
            Text(selectionCounter)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(model.theme.secondaryText)
            if !model.searchQuery.isEmpty {
                Text("“\(model.searchQuery)”")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.theme.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            shortcutHint("TAB", label: "CYCLE")
            shortcutHint("⌥", label: "SELECT")
        }
        .foregroundStyle(model.theme.accent)
        .padding(.horizontal, 17)
        .frame(height: 40)
    }

    @ViewBuilder
    private var content: some View {
        if model.windows.isEmpty {
            Text("No windows found for “\(model.searchQuery)”")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(model.theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: model.layout.requiresVerticalScrolling) {
                    LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                            AdaptiveWindowCard(
                                window: window,
                                preview: model.previews[window.id],
                                isSelected: index == model.selectedIndex,
                                index: index,
                                appearance: model.appearance,
                                previewSize: model.layout.previewSize,
                                itemSize: model.layout.itemSize,
                                theme: model.theme,
                                selectionEffect: model.selectionEffect,
                                livePreviewCoordinator: livePreviewCoordinator
                            )
                            .id(window.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, model.appearance == .windowTitles ? 9 : 10)
                }
                .onChange(of: model.selectedIndex) { _, newIndex in
                    guard model.windows.indices.contains(newIndex) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) {
                        proxy.scrollTo(model.windows[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(model.layout.itemSize.width), spacing: model.layout.horizontalSpacing),
            count: max(1, model.layout.columns)
        )
    }

    private var gridSpacing: CGFloat {
        model.layout.verticalSpacing
    }

    private var selectionCounter: String {
        guard model.windows.indices.contains(model.selectedIndex) else {
            return String(format: "00 / %02d", model.windows.count)
        }
        return String(format: "%02d / %02d", model.selectedIndex + 1, model.windows.count)
    }

    private var appearanceSymbol: String {
        switch model.appearance {
        case .thumbnails: "rectangle.stack"
        case .appIcons: "app.dashed"
        case .windowTitles: "list.bullet.rectangle"
        }
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

    @ViewBuilder
    private var panelBackground: some View {
        ZStack {
            if model.glassEnabled {
                Rectangle().fill(.ultraThinMaterial)
                model.theme.cardFill.opacity(0.44)
            } else {
                switch model.theme {
                case .game:
                    Color(red: 0.025, green: 0.045, blue: 0.048)
                case .classic:
                    Color(nsColor: .windowBackgroundColor)
                case .modern:
                    LinearGradient(
                        colors: [Color(red: 0.025, green: 0.022, blue: 0.075), Color(red: 0.065, green: 0.042, blue: 0.135)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            LinearGradient(
                colors: [model.theme.primaryText.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.screen)
        }
    }
}

private struct AdaptiveWindowCard: View {
    let window: WindowInfo
    let preview: WindowPreview?
    let isSelected: Bool
    let index: Int
    let appearance: SwitcherAppearance
    let previewSize: CGSize
    let itemSize: CGSize
    let theme: SwitcherTheme
    let selectionEffect: SwitcherSelectionEffect
    let livePreviewCoordinator: LivePreviewCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch appearance {
        case .thumbnails:
            thumbnailCard
        case .appIcons:
            decoratedCard(iconCard)
        case .windowTitles:
            decoratedCard(titleCard)
        }
    }

    private var thumbnailCard: some View {
        VStack(spacing: 8) {
            previewImage
                .overlay {
                    LiveWindowPreviewView(
                        windowID: window.id,
                        coordinator: livePreviewCoordinator
                    )
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) { indexBadge }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.accent, lineWidth: 2.5)
                    }
                }
                .shadow(color: isSelected ? theme.accent.opacity(0.20) : .clear, radius: 4)

            metadata(iconSize: max(24, min(28, itemSize.width * 0.085)))
                .frame(width: itemSize.width, height: 44)
        }
        .frame(width: itemSize.width, height: itemSize.height, alignment: .top)
        .opacity(isSelected ? 1 : 0.94)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title), \(window.applicationName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func decoratedCard<Content: View>(_ content: Content) -> some View {
        content
            .frame(width: itemSize.width, height: itemSize.height)
            .background(cardBackground)
            .overlay(selectionBorder)
            .overlay {
                SelectionEffectOverlay(
                    effect: selectionEffect,
                    theme: theme,
                    cornerRadius: cornerRadius,
                    isSelected: isSelected
                )
            }
            .shadow(color: isSelected ? theme.accent.opacity(0.34) : .clear, radius: 16)
            .opacity(isSelected ? 1 : 0.88)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(window.title), \(window.applicationName)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

    private var iconCard: some View {
        VStack(spacing: max(5, itemSize.height * 0.035)) {
            ApplicationIcon(window: window, size: max(38, min(82, itemSize.width * 0.44)))
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            Text(window.title)
                .font(.system(size: max(10, min(13, itemSize.width * 0.075)), weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(window.applicationName.uppercased())
                .font(.system(size: max(7, min(9, itemSize.width * 0.052)), weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                .lineLimit(1)
        }
        .padding(9)
        .overlay(alignment: .topLeading) { indexBadge }
    }

    private var titleCard: some View {
        HStack(spacing: 10) {
            ApplicationIcon(window: window, size: 30)
            Text(window.applicationName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                .lineLimit(1)
                .frame(width: min(112, itemSize.width * 0.29), alignment: .leading)
            Text(window.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .help("Minimized")
            }
        }
        .padding(.horizontal, 11)
    }

    private var previewImage: some View {
        ZStack {
            Color.black.opacity(0.18)
            if let preview {
                Image(decorative: preview.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ApplicationIcon(window: window, size: max(40, min(68, itemSize.width * 0.20)))
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipped()
    }

    private func metadata(iconSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            ApplicationIcon(window: window, size: iconSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.title)
                    .font(.system(size: max(10, min(12, itemSize.width * 0.042)), weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(window.applicationName.uppercased())
                    .font(.system(size: max(7, min(9, itemSize.width * 0.03)), weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var indexBadge: some View {
        Text(String(format: "%02d", index + 1))
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(isSelected ? Color.black : theme.primaryText.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? theme.accent : theme.cardFill.opacity(0.94))
            .padding(6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isSelected ? theme.selectedCardFill : theme.cardFill)
    }

    @ViewBuilder
    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(isSelected ? theme.accent : theme.primaryText.opacity(0.12), lineWidth: isSelected ? 2.2 : 1)
    }

    private var cornerRadius: CGFloat {
        appearance == .windowTitles ? 8 : 10
    }
}
