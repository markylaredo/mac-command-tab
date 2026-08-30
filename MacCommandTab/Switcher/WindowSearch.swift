import Foundation

struct WindowSearch: Sendable {
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func filter<Element>(
        _ elements: [Element],
        query: String,
        applicationName: (Element) -> String,
        title: (Element) -> String
    ) -> [Element] {
        let query = normalized(query)
        guard !query.isEmpty else { return elements }
        return elements.filter {
            applicationName($0).localizedCaseInsensitiveContains(query)
                || title($0).localizedCaseInsensitiveContains(query)
        }
    }

    static func filter(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        filter(
            windows,
            query: query,
            applicationName: \WindowInfo.applicationName,
            title: \WindowInfo.title
        )
    }

    static func selectionIndex<ID: Equatable>(
        preserving selectedID: ID?,
        visibleIDs: [ID]
    ) -> Int? {
        guard !visibleIDs.isEmpty else { return nil }
        guard let selectedID else { return 0 }
        return visibleIDs.firstIndex(of: selectedID) ?? 0
    }

    static func deletingLastCharacter(from query: String) -> String {
        guard !query.isEmpty else { return query }
        return String(query.dropLast())
    }
}
