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
        let headerHeight: CGFloat
        let minimumPanelWidth: CGFloat
    }

    func calculateLayout(
        itemCount: Int,
        availableSize: CGSize,
        appearance: SwitcherAppearance
    ) -> SwitcherLayout {
        let metrics = metrics(for: appearance)
        let maximumWidth = max(360, availableSize.width * 0.92)
        let maximumHeight = max(180, availableSize.height * 0.78)

        guard itemCount > 0 else {
            return SwitcherLayout(
                columns: 1,
                rows: 0,
                previewSize: .zero,
                itemSize: .zero,
                horizontalSpacing: metrics.horizontalSpacing,
                verticalSpacing: metrics.verticalSpacing,
                panelSize: CGSize(width: min(maximumWidth, 420), height: 92),
                requiresVerticalScrolling: false
            )
        }

        var best: (layout: SwitcherLayout, score: CGFloat)?
        for columns in 1...itemCount {
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            let widthLimit = (
                maximumWidth
                - metrics.horizontalPadding
                - CGFloat(columns - 1) * metrics.horizontalSpacing
            ) / CGFloat(columns)
            let heightLimit = (
                maximumHeight
                - metrics.headerHeight
                - metrics.verticalPadding
                - CGFloat(rows - 1) * metrics.verticalSpacing
            ) / CGFloat(rows)
            let cardWidth = fittedCardWidth(
                widthLimit: widthLimit,
                heightLimit: heightLimit,
                metrics: metrics
            )
            guard cardWidth >= metrics.emergencyMinimumWidth else { continue }

            let previewHeight = previewHeight(for: cardWidth, metrics: metrics)
            let itemHeight = itemHeight(for: cardWidth, metrics: metrics)
            let panelWidth = min(
                maximumWidth,
                max(
                    metrics.minimumPanelWidth,
                    CGFloat(columns) * cardWidth
                        + CGFloat(columns - 1) * metrics.horizontalSpacing
                        + metrics.horizontalPadding
                )
            )
            let panelHeight = min(
                maximumHeight,
                metrics.headerHeight
                    + metrics.verticalPadding
                    + CGFloat(rows) * itemHeight
                    + CGFloat(rows - 1) * metrics.verticalSpacing
            )
            let unusedSlots = columns * rows - itemCount
            let normalizedWidth = min(cardWidth, metrics.preferredWidth) / metrics.preferredWidth
            let readability = normalizedWidth * normalizedWidth * 1_000
            let normalSizeBonus: CGFloat = cardWidth >= metrics.normalMinimumWidth ? 160 : 0
            let wastePenalty = CGFloat(unusedSlots) * 34
            let panelRatio = panelWidth / max(panelHeight, 1)
            let targetRatio: CGFloat = appearance == .windowTitles ? 1.8 : 1.65
            let aspectPenalty = abs(panelRatio - targetRatio) * 18
            let score = readability + normalSizeBonus - wastePenalty - aspectPenalty
            let layout = SwitcherLayout(
                columns: columns,
                rows: rows,
                previewSize: CGSize(width: cardWidth, height: previewHeight),
                itemSize: CGSize(width: cardWidth, height: itemHeight),
                horizontalSpacing: metrics.horizontalSpacing,
                verticalSpacing: metrics.verticalSpacing,
                panelSize: CGSize(width: panelWidth, height: panelHeight),
                requiresVerticalScrolling: false
            )
            if best == nil || score > best!.score {
                best = (layout, score)
            }
        }

        if let best { return best.layout }
        return scrollingFallback(
            itemCount: itemCount,
            maximumWidth: maximumWidth,
            maximumHeight: maximumHeight,
            metrics: metrics
        )
    }

    private func fittedCardWidth(
        widthLimit: CGFloat,
        heightLimit: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let heightBoundWidth: CGFloat
        if let fixedHeight = metrics.fixedItemHeight {
            guard heightLimit >= fixedHeight else { return 0 }
            heightBoundWidth = metrics.preferredWidth
        } else {
            let previewHeightLimit = heightLimit - metrics.metadataSpacing - metrics.metadataHeight
            heightBoundWidth = max(0, previewHeightLimit) * metrics.previewAspectRatio
        }
        return floor(min(metrics.preferredWidth, widthLimit, heightBoundWidth))
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

    private func scrollingFallback(
        itemCount: Int,
        maximumWidth: CGFloat,
        maximumHeight: CGFloat,
        metrics: Metrics
    ) -> SwitcherLayout {
        let columns = max(
            1,
            Int((maximumWidth - metrics.horizontalPadding + metrics.horizontalSpacing)
                / (metrics.emergencyMinimumWidth + metrics.horizontalSpacing))
        )
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let widthLimit = (
            maximumWidth
            - metrics.horizontalPadding
            - CGFloat(columns - 1) * metrics.horizontalSpacing
        ) / CGFloat(columns)
        let cardWidth = max(1, floor(widthLimit))
        let previewHeight = previewHeight(for: cardWidth, metrics: metrics)
        let itemHeight = itemHeight(for: cardWidth, metrics: metrics)
        return SwitcherLayout(
            columns: columns,
            rows: rows,
            previewSize: CGSize(width: cardWidth, height: previewHeight),
            itemSize: CGSize(width: cardWidth, height: itemHeight),
            horizontalSpacing: metrics.horizontalSpacing,
            verticalSpacing: metrics.verticalSpacing,
            panelSize: CGSize(width: maximumWidth, height: maximumHeight),
            requiresVerticalScrolling: true
        )
    }

    private func metrics(for appearance: SwitcherAppearance) -> Metrics {
        switch appearance {
        case .thumbnails:
            Metrics(
                preferredWidth: 330,
                normalMinimumWidth: 180,
                emergencyMinimumWidth: 128,
                previewAspectRatio: 1.60,
                fixedItemHeight: nil,
                metadataHeight: 44,
                metadataSpacing: 8,
                horizontalSpacing: 12,
                verticalSpacing: 16,
                horizontalPadding: 28,
                verticalPadding: 20,
                headerHeight: 42,
                minimumPanelWidth: 320
            )
        case .appIcons:
            Metrics(
                preferredWidth: 180,
                normalMinimumWidth: 118,
                emergencyMinimumWidth: 88,
                previewAspectRatio: 1.08,
                fixedItemHeight: nil,
                metadataHeight: 0,
                metadataSpacing: 0,
                horizontalSpacing: 10,
                verticalSpacing: 10,
                horizontalPadding: 28,
                verticalPadding: 20,
                headerHeight: 42,
                minimumPanelWidth: 300
            )
        case .windowTitles:
            Metrics(
                preferredWidth: 410,
                normalMinimumWidth: 260,
                emergencyMinimumWidth: 210,
                previewAspectRatio: 6.8,
                fixedItemHeight: 58,
                metadataHeight: 0,
                metadataSpacing: 0,
                horizontalSpacing: 7,
                verticalSpacing: 7,
                horizontalPadding: 28,
                verticalPadding: 18,
                headerHeight: 42,
                minimumPanelWidth: 400
            )
        }
    }
}
