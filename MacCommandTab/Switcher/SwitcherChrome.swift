import SwiftUI

struct SwitcherSearchBar: View {
    let query: String
    let windowCount: Int
    let theme: SwitcherTheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Text(query.isEmpty ? "Search apps and windows…" : query)
                .font(.system(size: 13, weight: query.isEmpty ? .regular : .medium))
                .foregroundStyle(query.isEmpty ? theme.secondaryText : theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(windowCount == 1 ? "1 window" : "\(windowCount) windows")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(query.isEmpty ? "Search apps and windows" : "Search: \(query)")
    }
}

struct SwitcherFooter: View {
    let searchActive: Bool
    let theme: SwitcherTheme

    var body: some View {
        HStack(spacing: 18) {
            hint("⇥", "Navigate")
            hint("↵", "Open")
            Spacer(minLength: 8)
            hint("esc", searchActive ? "Clear search" : "Cancel")
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.primaryText.opacity(0.72))
            Text(action)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.secondaryText)
        }
    }
}

struct SwitcherEmptyState: View {
    let searchQuery: String
    let theme: SwitcherTheme

    var body: some View {
        VStack(spacing: 5) {
            Text(searchQuery.isEmpty ? "No windows available" : "No matching windows")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(
                searchQuery.isEmpty
                    ? "Open another application and try again."
                    : "Try another application or window name."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}
