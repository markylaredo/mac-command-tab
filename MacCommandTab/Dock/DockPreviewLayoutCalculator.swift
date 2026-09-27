import CoreGraphics
import Foundation

/// Where the Dock sits on screen. Determines which edge the preview panel grows
/// from.
enum DockScreenEdge: Equatable, Sendable {
    case bottom
    case left
    case right

    /// Reads the Dock's orientation from its preferences. This is a documented
    /// user default, not private API, and falls back to the bottom edge.
    static var current: DockScreenEdge {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

struct DockPreviewLayout: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let itemSize: CGSize
    let previewSize: CGSize
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let headerHeight: CGFloat
    let contentInsets: CGFloat
    /// Space reserved for the window title under each preview.
    let captionHeight: CGFloat
    let panelSize: CGSize
    let requiresScrolling: Bool
}

/// Sizes the Dock preview panel.
///
/// Mirrors `SwitcherLayoutCalculator`'s approach — pick a card size from the
/// window count, then clamp the panel into the usable area — but laid out
/// horizontally, anchored beside the Dock, and optimised for reading a small
/// group of windows at a glance rather than navigating a large grid.
struct DockPreviewLayoutCalculator: Sendable {
    static let maximumColumns = 5
    static let maximumVisibleRows = 2

    private let minimumItemWidth: CGFloat = 132
    private let maximumItemWidth: CGFloat = 340
    private let preferredAspectRatio: CGFloat = 16.0 / 10.0
    private let captionHeight: CGFloat = 20
    private let headerHeight: CGFloat = 34
    private let contentInsets: CGFloat = 14
    private let horizontalSpacing: CGFloat = 12
    private let verticalSpacing: CGFloat = 12
    /// Keeps the panel clear of the Dock rather than touching it.
    private let dockGap: CGFloat = 10

    func calculateLayout(
        itemCount: Int,
        availableSize: CGSize,
        dockEdge: DockScreenEdge,
        displayScale: CGFloat,
        preferredItemWidth: CGFloat = 240
    ) -> DockPreviewLayout {
        let available = CGSize(
            width: max(200, availableSize.width),
            height: max(160, availableSize.height)
        )

        guard itemCount > 0 else {
            return DockPreviewLayout(
                columns: 1,
                rows: 0,
                itemSize: .zero,
                previewSize: .zero,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing,
                headerHeight: headerHeight,
                contentInsets: contentInsets,
                captionHeight: captionHeight,
                panelSize: CGSize(width: 280, height: headerHeight + contentInsets * 2),
                requiresScrolling: false
            )
        }

        // A side Dock leaves less horizontal room, so the panel prefers fewer,
        // taller columns there.
        let columnLimit = dockEdge == .bottom
            ? Self.maximumColumns
            : min(Self.maximumColumns, 3)
        let maximumPanelWidth = available.width * 0.92
        let fittingColumns = max(1, Int((maximumPanelWidth - contentInsets * 2 + horizontalSpacing) / (minimumItemWidth + horizontalSpacing)))
        let columns = min(itemCount, columnLimit, fittingColumns)
        let rows = min(Self.maximumVisibleRows, Int(ceil(Double(itemCount) / Double(columns))))

        let maximumPanelHeight = available.height * 0.86

        // Solve for the item width that satisfies both the width and height
        // budgets, then clamp it. Taking the minimum of the two budgets keeps the
        // panel inside the screen on both axes without a second pass.
        let widthBudget = (
            maximumPanelWidth
                - contentInsets * 2
                - horizontalSpacing * CGFloat(columns - 1)
        ) / CGFloat(columns)

        let heightBudget = (
            maximumPanelHeight
                - headerHeight
                - contentInsets * 2
                - captionHeight * CGFloat(rows)
                - verticalSpacing * CGFloat(rows - 1)
        ) / CGFloat(rows) * preferredAspectRatio

        // The user's size is a ceiling. Dense groups shrink before scrolling.
        let preferredWidth = min(maximumItemWidth, max(160, preferredItemWidth))
        let densityScale = max(0.65, 1 - CGFloat(max(0, itemCount - 3)) * 0.045)
        let desiredWidth = max(minimumItemWidth, preferredWidth * densityScale)
        let scale = max(1, displayScale)
        let itemWidth = floor(min(desiredWidth, widthBudget, heightBudget) * scale) / scale

        // Very wide windows are common; cap the ratio so the grid stays even.
        let previewHeight = (itemWidth / preferredAspectRatio).rounded()
        let previewSize = CGSize(width: itemWidth.rounded(), height: previewHeight)
        let itemSize = CGSize(width: previewSize.width, height: previewSize.height + captionHeight)

        let contentWidth = itemSize.width * CGFloat(columns) + horizontalSpacing * CGFloat(columns - 1)
        let contentHeight = itemSize.height * CGFloat(rows) + verticalSpacing * CGFloat(rows - 1)
        let panelSize = CGSize(
            width: contentWidth + contentInsets * 2,
            height: contentHeight + headerHeight + contentInsets * 2
        )

        let fitsWithoutScrolling = panelSize.width <= maximumPanelWidth
            && panelSize.height <= maximumPanelHeight

        return DockPreviewLayout(
            columns: columns,
            rows: rows,
            itemSize: itemSize,
            previewSize: previewSize,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            headerHeight: headerHeight,
            contentInsets: contentInsets,
            captionHeight: captionHeight,
            panelSize: CGSize(
                width: min(panelSize.width, maximumPanelWidth),
                height: min(panelSize.height, maximumPanelHeight)
            ),
            requiresScrolling: !fitsWithoutScrolling || itemCount > columns * rows
        )
    }

    /// Positions the panel next to `dockFrame`, growing away from the Dock and
    /// staying inside `visibleFrame`.
    ///
    /// `dockFrame` is the hovered tile, so the panel is centred on the tile the
    /// user is actually pointing at rather than on the Dock as a whole.
    func panelOrigin(
        panelSize: CGSize,
        dockFrame: CGRect?,
        dockEdge: DockScreenEdge,
        visibleFrame: CGRect
    ) -> CGPoint {
        let anchor = dockFrame ?? defaultAnchor(for: dockEdge, in: visibleFrame)

        var origin = CGPoint.zero
        switch dockEdge {
        case .bottom:
            origin.x = anchor.midX - panelSize.width / 2
            origin.y = anchor.maxY + dockGap
        case .left:
            origin.x = anchor.maxX + dockGap
            origin.y = anchor.midY - panelSize.height / 2
        case .right:
            origin.x = anchor.minX - dockGap - panelSize.width
            origin.y = anchor.midY - panelSize.height / 2
        }

        return clamp(origin: origin, panelSize: panelSize, visibleFrame: visibleFrame)
    }

    private func defaultAnchor(for dockEdge: DockScreenEdge, in visibleFrame: CGRect) -> CGRect {
        let thickness: CGFloat = 60
        switch dockEdge {
        case .bottom:
            return CGRect(
                x: visibleFrame.midX - 30,
                y: visibleFrame.minY - thickness,
                width: 60,
                height: thickness
            )
        case .left:
            return CGRect(x: visibleFrame.minX - thickness, y: visibleFrame.midY - 30, width: thickness, height: 60)
        case .right:
            return CGRect(x: visibleFrame.maxX, y: visibleFrame.midY - 30, width: thickness, height: 60)
        }
    }

    /// Clamps the panel fully inside the usable area. A panel that would extend
    /// past an edge slides inward rather than being resized, so content stays
    /// readable.
    private func clamp(origin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }
}
