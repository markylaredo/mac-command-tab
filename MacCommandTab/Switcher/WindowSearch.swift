import Foundation

/// The outcome of a window search.
///
/// `isWidened` reports that the query produced no full-query match and the
/// results came from token-level recall. Callers may use it to explain a result
/// set that looks looser than the query, but nothing depends on it: the ranking
/// is already expressed in the returned order.
struct WindowSearchOutcome<Element> {
    let elements: [Element]
    let isWidened: Bool
}

/// Ranks windows against a typed query.
///
/// Search runs in two phases. The path is synchronous and allocation-light
/// because it executes inside the event-tap callback on the main actor, on every
/// keystroke, before the switcher can update.
///
/// **Phase one — whole-query matching.** The six documented rank classes, applied
/// to the query as a whole. This is unchanged and remains authoritative: a query
/// that matches literally is answered exactly as before.
///
/// **Phase two — token-coverage recall.** Only reached when phase one finds
/// nothing and the query has at least two whitespace-separated tokens. Windows
/// are scored by how many of the query's tokens they account for across the
/// application name and the window title, and ordered by coverage.
///
/// Phase two exists because the two fields are matched independently and a
/// multi-token query is a single string: "OMECO Rider" matches neither
/// "Omeco.ApiV2 – Rider" (the token "omeco" alone does not contain the query) nor
/// anything else, even though one window accounts for both tokens. Splitting the
/// query recovers those windows.
///
/// A candidate is accepted only when **every** token in the query appears
/// somewhere in its application name or window title. The tokens need not be
/// adjacent, and may come from different fields. Requiring all of them is what
/// keeps recall bounded: the tokens are individually weak, and accepting a subset
/// would drag in every window that shares one common word with the query.
enum WindowSearch {
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Ranks `elements` against `query`, reporting whether token widening was used.
    static func ranked<Element>(
        _ elements: [Element],
        query: String,
        applicationName: (Element) -> String,
        title: (Element) -> String
    ) -> WindowSearchOutcome<Element> {
        let query = normalized(query)
        guard !query.isEmpty else {
            return WindowSearchOutcome(elements: elements, isWidened: false)
        }

        let matched = elements.enumerated().compactMap { offset, element -> (Element, Int, Int)? in
            guard let rank = rank(
                applicationName: applicationName(element),
                title: title(element),
                query: query
            ) else { return nil }
            return (element, rank, offset)
        }.sorted {
            $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1
        }.map(\.0)

        guard matched.isEmpty else {
            return WindowSearchOutcome(elements: matched, isWidened: false)
        }

        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 1 else {
            return WindowSearchOutcome(elements: [], isWidened: false)
        }

        // Every token must be accounted for. Accumulating into a score and
        // comparing it against the token count is what allows the tokens to be
        // spread across the application name and the title independently.
        let widened = elements.enumerated().compactMap { offset, element -> (Element, Int, Int)? in
            let app = normalized(applicationName(element))
            let windowTitle = normalized(title(element))
            var covered = 0
            var bestFieldRank = Int.max
            for token in tokens {
                if app.contains(token) {
                    covered += 1
                    bestFieldRank = min(bestFieldRank, 0)
                } else if windowTitle.contains(token) {
                    covered += 1
                    bestFieldRank = min(bestFieldRank, 1)
                }
            }
            guard covered == tokens.count else { return nil }
            return (element, bestFieldRank, offset)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }.map(\.0)

        return WindowSearchOutcome(elements: widened, isWidened: !widened.isEmpty)
    }

    /// Convenience accessor for callers that only need the ordered results.
    static func filter<Element>(
        _ elements: [Element],
        query: String,
        applicationName: (Element) -> String,
        title: (Element) -> String
    ) -> [Element] {
        ranked(
            elements,
            query: query,
            applicationName: applicationName,
            title: title
        ).elements
    }

    static func filter(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        filter(
            windows,
            query: query,
            applicationName: \WindowInfo.applicationName,
            title: \WindowInfo.title
        )
    }

    /// The documented rank classes. Lower is a stronger match.
    private static func rank(applicationName: String, title: String, query: String) -> Int? {
        let app = normalized(applicationName)
        let windowTitle = normalized(title)
        if app == query { return 0 }
        if app.hasPrefix(query) { return 1 }
        if windowTitle == query { return 2 }
        if windowTitle.hasPrefix(query) { return 3 }
        if app.localizedCaseInsensitiveContains(query) { return 4 }
        if windowTitle.localizedCaseInsensitiveContains(query) { return 5 }
        return nil
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
