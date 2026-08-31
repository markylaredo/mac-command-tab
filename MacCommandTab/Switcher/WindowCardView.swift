import SwiftUI

struct ApplicationIcon: View {
    let window: WindowInfo
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: renderedSize, height: renderedSize)
        .accessibilityHidden(true)
    }

    private var renderedSize: CGFloat {
        max(1, size.rounded())
    }
}
