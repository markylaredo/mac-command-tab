import CoreGraphics

struct SwitcherLayout: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let previewSize: CGSize
    let itemSize: CGSize
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let panelSize: CGSize
    let requiresVerticalScrolling: Bool

    var cardSize: CGSize { itemSize }

    static let empty = SwitcherLayout(
        columns: 1,
        rows: 0,
        previewSize: .zero,
        itemSize: .zero,
        horizontalSpacing: 0,
        verticalSpacing: 0,
        panelSize: CGSize(width: 360, height: 92),
        requiresVerticalScrolling: false
    )
}

struct SwitcherLayoutCalculator: Sendable {
    private struct Metrics {
        let preferredWidth: CGFloat
        let normalMinimumWidth: CGFloat
        let emergencyMinimumWidth: CGFloat
        let previewAspectRatio: CGFloat
        let fixedItemHeight: CGFloat?
        let metadataHeight: CGFloat
        let metadataSpacing: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let minimumPanelWidth: CGFloat
        let maximumPanelWidth: CGFloat
    }

    func calculateLayout(
        itemCount: Int,
        availableSize: CGSize,
        appearance: SwitcherAppearance,
        searchActive: Bool = false
    ) -> SwitcherLayout {
        let metrics = metrics(for: appearance)
        let maximumWidth = min(
            metrics.maximumPanelWidth,
            max(metrics.minimumPanelWidth, availableSize.width * 0.92)
        )
        let maximumHeight = max(160, availableSize.height * 0.78)
        let chromeHeight: CGFloat = 48 + 34

        guard itemCount > 0 else {
            return SwitcherLayout(
                columns: 1,
                rows: 0,
                previewSize: .zero,
                itemSize: .zero,
                horizontalSpacing: metrics.horizontalSpacing,
                verticalSpacing: metrics.verticalSpacing,
                panelSize: CGSize(
                    width: min(maximumWidth, searchActive ? 440 : 280),
                    height: chromeHeight + 88
                ),
                requiresVerticalScrolling: false
            )
        }

        let adaptiveWidth = adaptivePreferredWidth(
            metrics.preferredWidth,
            availableWidth: availableSize.width,
            appearance: appearance
        )
        let densityScale: CGFloat
        switch itemCount {
        case ...10: densityScale = 1
        case 11...20: densityScale = 0.92
        default: densityScale = 0.82
        }
        let preferredWidth = max(metrics.emergencyMinimumWidth, floor(adaptiveWidth * densityScale))
        let oneRowWidth = floor(
            (maximumWidth
                - metrics.horizontalPadding
                - CGFloat(max(0, itemCount - 1)) * metrics.horizontalSpacing)
                / CGFloat(itemCount)
        )
        let preferredColumns = max(
            1,
            Int((maximumWidth - metrics.horizontalPadding + metrics.horizontalSpacing)
                / (preferredWidth + metrics.horizontalSpacing))
        )
        let columns: Int
        if oneRowWidth >= metrics.normalMinimumWidth {
            columns = itemCount
        } else {
            let preferredRows = Int(ceil(Double(itemCount) / Double(preferredColumns)))
            columns = Int(ceil(Double(itemCount) / Double(preferredRows)))
        }
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let widthLimit = (
            maximumWidth
            - metrics.horizontalPadding
            - CGFloat(columns - 1) * metrics.horizontalSpacing
        ) / CGFloat(columns)
        let cardWidth = floor(max(metrics.emergencyMinimumWidth, min(preferredWidth, widthLimit)))
        let previewHeight = previewHeight(for: cardWidth, metrics: metrics)
        let itemHeight = itemHeight(for: cardWidth, metrics: metrics)
        let contentHeight = chromeHeight
            + metrics.verticalPadding
            + CGFloat(rows) * itemHeight
            + CGFloat(max(0, rows - 1)) * metrics.verticalSpacing
        let panelWidth = min(
            maximumWidth,
            max(
                metrics.minimumPanelWidth,
                CGFloat(columns) * cardWidth
                    + CGFloat(max(0, columns - 1)) * metrics.horizontalSpacing
                    + metrics.horizontalPadding
            )
        )
        return SwitcherLayout(
            columns: columns,
            rows: rows,
            previewSize: CGSize(width: cardWidth, height: previewHeight),
            itemSize: CGSize(width: cardWidth, height: itemHeight),
            horizontalSpacing: metrics.horizontalSpacing,
            verticalSpacing: metrics.verticalSpacing,
            panelSize: CGSize(width: panelWidth, height: min(maximumHeight, contentHeight)),
            requiresVerticalScrolling: contentHeight > maximumHeight
        )
    }

    private func adaptivePreferredWidth(
        _ preferredWidth: CGFloat,
        availableWidth: CGFloat,
        appearance: SwitcherAppearance
    ) -> CGFloat {
        guard appearance == .thumbnails else { return preferredWidth }
        switch availableWidth {
        case ..<1_300: return 150
        case ..<1_900: return 165
        default: return 175
        }
    }

    private func previewHeight(for width: CGFloat, metrics: Metrics) -> CGFloat {
        guard metrics.fixedItemHeight == nil else { return metrics.fixedItemHeight ?? 0 }
        return floor(width / metrics.previewAspectRatio)
    }

    private func itemHeight(for width: CGFloat, metrics: Metrics) -> CGFloat {
        if let fixedItemHeight = metrics.fixedItemHeight { return fixedItemHeight }
        return previewHeight(for: width, metrics: metrics)
            + metrics.metadataSpacing
            + metrics.metadataHeight
    }

    private func metrics(for appearance: SwitcherAppearance) -> Metrics {
        switch appearance {
        case .thumbnails:
            Metrics(
                preferredWidth: 165,
                normalMinimumWidth: 130,
                emergencyMinimumWidth: 125,
                previewAspectRatio: 1.66,
                fixedItemHeight: nil,
                metadataHeight: 40,
                metadataSpacing: 8,
                horizontalSpacing: 14,
                verticalSpacing: 14,
                horizontalPadding: 40,
                verticalPadding: 32,
                minimumPanelWidth: 240,
                maximumPanelWidth: 1_560
            )
        case .appIcons:
            Metrics(
                preferredWidth: 154,
                normalMinimumWidth: 118,
                emergencyMinimumWidth: 88,
                previewAspectRatio: 1.08,
                fixedItemHeight: nil,
                metadataHeight: 0,
                metadataSpacing: 0,
                horizontalSpacing: 10,
                verticalSpacing: 10,
                horizontalPadding: 40,
                verticalPadding: 32,
                minimumPanelWidth: 220,
                maximumPanelWidth: 1_360
            )
        case .windowTitles:
            Metrics(
                preferredWidth: 360,
                normalMinimumWidth: 260,
                emergencyMinimumWidth: 210,
                previewAspectRatio: 6.8,
                fixedItemHeight: 54,
                metadataHeight: 0,
                metadataSpacing: 0,
                horizontalSpacing: 7,
                verticalSpacing: 7,
                horizontalPadding: 40,
                verticalPadding: 26,
                minimumPanelWidth: 360,
                maximumPanelWidth: 1_440
            )
        }
    }
}
