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
        return elements.enumerated().compactMap { offset, element -> (Element, Int, Int)? in
            let app = normalized(applicationName(element))
            let windowTitle = normalized(title(element))
            let rank: Int
            if app == query { rank = 0 }
            else if app.hasPrefix(query) { rank = 1 }
            else if windowTitle == query { rank = 2 }
            else if windowTitle.hasPrefix(query) { rank = 3 }
            else if app.localizedCaseInsensitiveContains(query) { rank = 4 }
            else if windowTitle.localizedCaseInsensitiveContains(query) { rank = 5 }
            else { return nil }
            return (element, rank, offset)
        }.sorted {
            $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1
        }.map(\.0)
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
