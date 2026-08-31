import SwiftUI

struct AdaptiveSwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    let livePreviewCoordinator: LivePreviewCoordinator
    let onHoverSelection: (Int) -> Void
    let onClickSelection: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            SwitcherSearchBar(
                query: model.searchQuery,
                windowCount: model.windows.count,
                theme: model.theme
            )
            content
            SwitcherFooter(searchActive: !model.searchQuery.isEmpty, theme: model.theme)
        }
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorSchemeContrast == .increased ? 0.38 : 0.22),
                            Color.white.opacity(colorSchemeContrast == .increased ? 0.14 : 0.055)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.layout)
    }

    @ViewBuilder
    private var content: some View {
        if model.windows.isEmpty {
            SwitcherEmptyState(searchQuery: model.searchQuery, theme: model.theme)
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
                                livePreviewCoordinator: livePreviewCoordinator,
                                onHoverSelection: onHoverSelection,
                                onClickSelection: onClickSelection
                            )
                            .id(window.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.top, model.appearance == .windowTitles ? 12 : 18)
                    .padding(.bottom, 14)
                }
                .onChange(of: model.selectedIndex) { _, newIndex in
                    guard model.windows.indices.contains(newIndex) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) {
                        proxy.scrollTo(model.windows[newIndex].id, anchor: .center)
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.17),
                    value: model.windows.map(\.id)
                )
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

    @ViewBuilder
    private var panelBackground: some View {
        ZStack {
            if model.glassEnabled, !reduceTransparency {
                Color.black.opacity(model.theme == .classic ? 0.05 : 0.16)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(0.98)
            }
            model.theme.accent.opacity(model.glassEnabled && !reduceTransparency ? 0.025 : 0.015)
        }
    }
}

enum WindowIdentityLayout {
    static func aspectFit(sourceSize: CGSize, in availableSize: CGSize) -> CGSize {
        let sourceRatio = sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
        let ratio = min(max(sourceRatio, 0.68), 2.0)
        let maximum = CGSize(
            width: max(1, availableSize.width - 20),
            height: max(1, availableSize.height - 14)
        )

        if maximum.width / maximum.height > ratio {
            return CGSize(width: maximum.height * ratio, height: maximum.height)
        }
        return CGSize(width: maximum.width, height: maximum.width / ratio)
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
    let livePreviewCoordinator: LivePreviewCoordinator
    let onHoverSelection: (Int) -> Void
    let onClickSelection: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Group {
            switch appearance {
            case .thumbnails:
                thumbnailCard
            case .appIcons:
                decoratedCard(iconCard)
            case .windowTitles:
                decoratedCard(titleCard)
            }
        }
        .overlay { selectionRing }
        .overlay(alignment: .bottom) { selectionIndicator }
        .scaleEffect(isSelected ? 1.025 : (isHovered ? 1.008 : 1))
        .offset(y: isSelected && !reduceMotion ? -2 : 0)
        .brightness(isSelected ? 0 : -0.015)
        .opacity(isSelected ? 1 : 0.84)
        .shadow(
            color: .black.opacity(isSelected ? 0.28 : 0.10),
            radius: isSelected ? 18 : 5,
            y: isSelected ? 9 : 3
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.20 : 0),
            radius: isSelected ? 3 : 0,
            y: isSelected ? 2 : 0
        )
        .zIndex(isSelected ? 1 : 0)
        .contentShape(Rectangle())
        .animation(selectionAnimation, value: isSelected)
        .animation(hoverAnimation, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHoverSelection(index) }
        }
        .onTapGesture { onClickSelection(index) }
    }

    private var thumbnailCard: some View {
        VStack(spacing: 8) {
            identitySurface

            metadata(iconSize: 18)
                .frame(width: itemSize.width, height: 40)
        }
        .frame(width: itemSize.width, height: itemSize.height, alignment: .top)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title), \(window.applicationName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func decoratedCard<Content: View>(_ content: Content) -> some View {
        content
            .frame(width: itemSize.width, height: itemSize.height)
            .background(cardBackground)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(window.title), \(window.applicationName)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconCard: some View {
        VStack(spacing: max(5, itemSize.height * 0.035)) {
            ApplicationIcon(window: window, size: isSelected ? 44 : 38)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            Text(window.title)
                .font(.system(size: max(11, min(13, itemSize.width * 0.078)), weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(window.applicationName)
                .font(.system(size: max(9.5, min(10.5, itemSize.width * 0.064)), weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            if let stateLabel {
                Text(stateLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.secondaryText.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .padding(9)
    }

    private var titleCard: some View {
        HStack(spacing: 10) {
            ApplicationIcon(window: window, size: isSelected ? 32 : 30)
                .frame(width: 32, height: 32)
            Text(window.applicationName)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .frame(width: min(112, itemSize.width * 0.29), alignment: .leading)
            Text(window.title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            inlineStateIndicators
        }
        .padding(.horizontal, 11)
    }

    private var identitySurface: some View {
        GeometryReader { proxy in
            let windowSize = WindowIdentityLayout.aspectFit(sourceSize: window.frame.size, in: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.12 : (isHovered ? 0.085 : 0.065)),
                                Color.white.opacity(isSelected ? 0.055 : 0.025)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.07 : 0.045), lineWidth: 1)
                    }

                livePreviewSurface(size: windowSize)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
    }

    private func livePreviewSurface(size windowSize: CGSize) -> some View {
        ZStack {
            if let preview {
                Image(decorative: preview.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: windowSize.width, height: windowSize.height)
                    .clipped()
                    .id(preview.id)
                    .transition(.opacity)
            } else {
                previewPlaceholder
            }

            LiveWindowPreviewView(
                windowID: window.id,
                coordinator: livePreviewCoordinator
            )
            .id(window.id)

            stateIndicators
                .padding(8)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.11 : 0.065), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(isSelected ? 0.25 : 0.13),
            radius: isSelected ? 10 : 4,
            y: isSelected ? 5 : 2
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: preview?.id)
    }

    private var previewPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.035)],
                startPoint: .top,
                endPoint: .bottom
            )
            ApplicationIcon(window: window, size: isSelected ? 44 : 40)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.24), radius: isSelected ? 6 : 4, y: 3)
        }
        .onAppear {
            LivePreviewDiagnostics.log("placeholder id=\(window.id.rawValue) reason=no-valid-frame")
        }
    }

    private func metadata(iconSize: CGFloat) -> some View {
        HStack(spacing: 7) {
            ApplicationIcon(window: window, size: isSelected ? 20 : iconSize)
                .frame(width: 22, height: 22)
                .opacity(isSelected ? 1 : 0.82)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.applicationName)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.primaryText.opacity(isSelected ? 1 : 0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(window.title)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(isSelected ? 0.025 : (isHovered ? 0.016 : 0.008)))
    }

    private var cornerRadius: CGFloat {
        appearance == .windowTitles ? 10 : 12
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    private var selectionIndicator: some View {
        Capsule(style: .continuous)
            .fill(theme.accent.opacity(0.86))
            .frame(width: 28, height: 3)
            .opacity(isSelected ? 1 : 0)
            .offset(y: 7)
            .accessibilityHidden(true)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(theme.accent.opacity(isSelected ? 0.78 : 0), lineWidth: 1.5)
            .padding(1)
            .accessibilityHidden(true)
    }

    private var stateIndicators: some View {
        HStack(spacing: 5) {
            if window.isMinimized { stateSymbol("minus.rectangle") }
            if window.isFullscreen { stateSymbol("arrow.up.left.and.arrow.down.right") }
            if window.isApplicationHidden { stateSymbol("eye.slash") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var inlineStateIndicators: some View {
        HStack(spacing: 6) {
            if window.isMinimized { stateSymbol("minus.rectangle") }
            if window.isFullscreen { stateSymbol("arrow.up.left.and.arrow.down.right") }
            if window.isApplicationHidden { stateSymbol("eye.slash") }
        }
    }

    private var stateLabel: String? {
        if window.isMinimized { return "Minimized" }
        if window.isApplicationHidden { return "Hidden" }
        if window.isFullscreen { return "Full Screen" }
        return nil
    }

    private func stateSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.secondaryText.opacity(0.82))
            .accessibilityHidden(true)
    }
}
