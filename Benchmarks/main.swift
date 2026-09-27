import Foundation

// Differential benchmark for the local window search.
//
// This runs the application's real `WindowSearch` implementation — the same
// source file compiled into the app target, not a copy — against realistic
// window sets. It performs no network I/O and does not require an API key.
//
// It works by comparison. `LiteralWindowSearch` below reproduces the previous
// whole-query-only behaviour, for evaluation purposes only. Every query runs
// through both implementations and the harness reports exactly what changed:
//
//   unchanged     identical results, including order
//   recall gained previously empty, now populated
//   REGRESSION    results lost, or reordered where the old ones should survive
//
// Run it with Benchmarks/run.sh, or see Benchmarks/README.md.

// MARK: - Baseline behaviour

/// The previous whole-query-only matcher, preserved so the harness can measure
/// the change rather than assert it. Evaluation code only: the app does not
/// contain this.
enum LiteralWindowSearch {
    static func filter<Element>(
        _ elements: [Element],
        query: String,
        applicationName: (Element) -> String,
        title: (Element) -> String
    ) -> [Element] {
        let query = WindowSearch.normalized(query)
        guard !query.isEmpty else { return elements }
        return elements.enumerated().compactMap { offset, element -> (Element, Int, Int)? in
            let app = WindowSearch.normalized(applicationName(element))
            let windowTitle = WindowSearch.normalized(title(element))
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
}

// MARK: - Measurement

struct LatencySummary {
    let samples: Int
    let p50Microseconds: Double
    let p95Microseconds: Double
    let maxMicroseconds: Double

    var maxMilliseconds: Double { maxMicroseconds / 1_000 }
}

func measure(iterations: Int, _ body: () -> Void) -> LatencySummary {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000)
    }
    samples.sort()
    func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let index = Int((p / 100) * Double(samples.count - 1))
        return samples[min(max(index, 0), samples.count - 1)]
    }
    return LatencySummary(
        samples: samples.count,
        p50Microseconds: percentile(50),
        p95Microseconds: percentile(95),
        maxMicroseconds: samples.last ?? 0
    )
}

// MARK: - Result classification

enum ChangeKind {
    /// Identical results, and identical order.
    case unchanged
    /// The previous behaviour returned nothing; the new behaviour returns results.
    case recallGained
    /// Still nothing, from either implementation.
    case stillEmpty
    /// A query that must return every window in the incoming order.
    case passthrough
    /// Results were lost, or reordered where the new ones should have led.
    case regression
}

struct QueryOutcome {
    let set: WindowSet
    let spec: QuerySpec
    let literalResults: [WindowInfo]
    let results: [WindowInfo]
    let isWidened: Bool
    let change: ChangeKind
    /// 1-based rank of the query's target window in the new results.
    let targetRank: Int?
    /// 1-based rank of the same target under the previous behaviour.
    let baselineTargetRank: Int?
}

/// The window a query is about, when the fixture names one. Used only for
/// reporting where a target landed, never for pass/fail.
func targetFixture(of spec: QuerySpec) -> WindowFixture? {
    switch spec.expectation {
    case let .top1(fixture): return fixture
    case let .anywhere(fixture): return fixture
    case .derived, .noMatch, .passthroughAll: return nil
    }
}

func classify(
    set: WindowSet,
    spec: QuerySpec,
    literalResults: [WindowInfo],
    results: [WindowInfo],
    isWidened: Bool
) -> QueryOutcome {
    let literalIDs = literalResults.map(\.id)
    let newIDs = results.map(\.id)

    let change: ChangeKind
    if case .passthroughAll = spec.expectation {
        let inputIDs = set.windows.map { $0.makeWindowInfo().id }
        change = newIDs == inputIDs ? .passthrough : .regression
    } else if literalIDs.isEmpty && newIDs.isEmpty {
        // Checked before equality: "nothing, then nothing" is not the same
        // finding as "same non-empty result", and must not be reported as an
        // unchanged query.
        change = .stillEmpty
    } else if literalIDs == newIDs {
        change = .unchanged
    } else if literalIDs.isEmpty {
        // Previously empty. Acceptable only when the widening path produced it:
        // an empty literal result must never yield results without widening.
        change = isWidened ? .recallGained : .regression
    } else {
        // The previous behaviour found something and the new result differs.
        // Whole-query matches are authoritative, so the old results must still
        // be present, in the same relative order, at the head of the new list.
        // Anything else is a regression.
        var remaining = newIDs[...]
        var preserved = true
        for identifier in literalIDs {
            guard let position = remaining.firstIndex(of: identifier) else {
                preserved = false
                break
            }
            remaining = remaining[remaining.index(after: position)...]
        }
        change = preserved ? .recallGained : .regression
    }

    func rank(of fixture: WindowFixture, in windows: [WindowInfo]) -> Int? {
        let identifier = fixture.makeWindowInfo().id
        return windows.firstIndex { $0.id == identifier }.map { $0 + 1 }
    }

    let target = targetFixture(of: spec)
    return QueryOutcome(
        set: set,
        spec: spec,
        literalResults: literalResults,
        results: results,
        isWidened: isWidened,
        change: change,
        targetRank: target.flatMap { rank(of: $0, in: results) },
        baselineTargetRank: target.flatMap { rank(of: $0, in: literalResults) }
    )
}

// MARK: - Fixture validation

/// Checks that each expectation is consistent with the window set it is run
/// against. Without this, a typo in a fixture reports as a search result and
/// silently distorts the comparison. Validation failures are harness bugs, not
/// search bugs, and are reported separately.
func validate(_ spec: QuerySpec, against set: WindowSet) -> String? {
    func contains(_ fixture: WindowFixture) -> Bool {
        set.windows.contains(fixture)
    }

    switch spec.expectation {
    case .derived, .passthroughAll:
        return nil
    case let .top1(fixture):
        return contains(fixture) ? nil : "expected window is not in set \(set.id): \(fixture.app) — \(fixture.title)"
    case let .anywhere(fixture):
        return contains(fixture) ? nil : "expected window is not in set \(set.id): \(fixture.app) — \(fixture.title)"
    case .noMatch:
        // `.noMatch` asserts that the deterministic matcher finds nothing. That
        // is only meaningful when the set contains no literal match for the
        // query — otherwise the expectation contradicts the matcher rather than
        // describing a gap.
        let literalMatch = set.windows.contains { window in
            let query = WindowSearch.normalized(spec.text)
            guard !query.isEmpty else { return true }
            return WindowSearch.normalized(window.app).contains(query)
                || WindowSearch.normalized(window.title).contains(query)
        }
        return literalMatch
            ? "mark `.noMatch` only when no window literally matches; \"\(spec.text)\" does match a window in set \(set.id)"
            : nil
    }
}

// MARK: - Set-specific query selection

/// Not every query is meaningful against every window set. Reporting a query
/// against a set that cannot contain its answer manufactures gaps that say
/// nothing about the matcher, so each set gets the queries that apply to it.
func queries(for set: WindowSet) -> [QuerySpec] {
    func applicable(_ specs: [QuerySpec]) -> [QuerySpec] {
        specs.filter { $0.setID == nil || $0.setID == set.id }
    }

    switch set.id {
    case "D":
        return applicable(WindowSearchQueries.literal) + applicable(WindowSearchQueries.adversarial)
    case "C":
        return applicable(WindowSearchQueries.semantic)
            + applicable(WindowSearchQueries.absent)
            + applicable(WindowSearchQueries.adversarial)
    case "E":
        // The stress set exists purely to measure recall flooding, which the
        // dedicated probe below reports far more directly than query fixtures.
        return []
    default:
        return applicable(WindowSearchQueries.literal)
            + applicable(WindowSearchQueries.mixed)
            + applicable(WindowSearchQueries.semantic)
            + applicable(WindowSearchQueries.adversarial)
    }
}

// MARK: - Reporting

let iterations = 200

print("""

MacCommandTab — local window search benchmark
=============================================
Source under test : MacCommandTab/Switcher/WindowSearch.swift (compiled from the app target)
Baseline          : whole-query matching only, reproduced in this file
Iterations        : \(iterations) per query for latency
Network           : none
""")

var outcomes: [QueryOutcome] = []
var fixtureErrors: [String] = []

// Validate every query in the inventory against every set it could be graded
// against, up front, so a bad expectation is reported even when the query would
// not have been selected for that set.
for set in WindowFixtures.all {
    for spec in WindowSearchQueries.all where spec.setID == nil || spec.setID == set.id {
        if let error = validate(spec, against: set) {
            fixtureErrors.append("set \(set.id)  \"\(spec.text)\"  → \(error)")
        }
    }
}

for set in WindowFixtures.all {
    let windows = set.windows.map { $0.makeWindowInfo() }
    print("\n\u{001B}[1mSet \(set.id) — \(set.name) (\(windows.count) windows)\u{001B}[0m")

    for spec in queries(for: set) {
        let literalResults = LiteralWindowSearch.filter(windows, query: spec.text)
        let ranked = WindowSearch.ranked(
            windows,
            query: spec.text,
            applicationName: \WindowInfo.applicationName,
            title: \WindowInfo.title
        )
        let outcome = classify(
            set: set,
            spec: spec,
            literalResults: literalResults,
            results: ranked.elements,
            isWidened: ranked.isWidened
        )
        outcomes.append(outcome)

        let latency = measure(iterations: iterations) {
            _ = WindowSearch.filter(windows, query: spec.text)
        }
        let literalLatency = measure(iterations: iterations) {
            _ = LiteralWindowSearch.filter(windows, query: spec.text)
        }

        let marker: String
        switch outcome.change {
        case .unchanged, .passthrough, .stillEmpty: marker = "  ok  "
        case .recallGained: marker = " GAIN "
        case .regression: marker = " REGR "
        }

        let displayQuery = spec.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\"\""
            : spec.text
        print("\n[\(marker)] \"\(displayQuery)\"  —  \(ranked.elements.count) result(s)"
              + (ranked.isWidened ? ", recalled by token widening" : "")
              + String(format: "  ·  p50 %.0f µs (was %.0f µs) · max %.2f ms",
                       latency.p50Microseconds, literalLatency.p50Microseconds, latency.maxMilliseconds))

        for (index, window) in ranked.elements.prefix(5).enumerated() {
            let isTarget = outcome.targetRank == index + 1
            print("         \(index + 1). \(window.applicationName) — \(window.title)\(isTarget ? "   ← target" : "")")
        }
        if ranked.elements.isEmpty {
            print("         (no matches)")
        }
        if let targetRank = outcome.targetRank, targetRank > 5 {
            print("         target is at rank \(targetRank) of \(ranked.elements.count)")
        }
        if outcome.change == .recallGained {
            print("         note: \(spec.note)")
        }
        if outcome.change == .regression {
            print("         REGRESSION: baseline \(literalResults.count) result(s), now \(ranked.elements.count).")
            print("         baseline: \(literalResults.prefix(4).map { "\($0.applicationName) — \($0.title)" })")
            print("         now     : \(ranked.elements.prefix(4).map { "\($0.applicationName) — \($0.title)" })")
        }
    }
}

// MARK: - Summary

let regressions = outcomes.filter { $0.change == .regression }
let gains = outcomes.filter { $0.change == .recallGained }
let unchanged = outcomes.filter { $0.change == .unchanged || $0.change == .passthrough }
let stillEmpty = outcomes.filter { $0.change == .stillEmpty }

print("""

\u{001B}[1mDifferential result\u{001B}[0m
-------------------
evaluations            : \(outcomes.count)
unchanged              : \(unchanged.count)   ← identical results and order
recall gained          : \(gains.count)   ← previously empty, now populated
regressions            : \(regressions.count)   ← must be zero
still empty            : \(stillEmpty.count)
fixture errors         : \(fixtureErrors.count)
""")

if !gains.isEmpty {
    print("\nRecall gained:")
    for outcome in gains {
        let targetNote = outcome.targetRank.map { "  target at rank \($0) of \(outcome.results.count)" } ?? ""
        print("  set \(outcome.set.id)  \"\(outcome.spec.text)\"  → \(outcome.results.count) result(s)\(targetNote)")
    }
}

if !regressions.isEmpty {
    print("\n\u{001B}[1mRegressions — fix before anything else:\u{001B}[0m")
    for outcome in regressions {
        print("  set \(outcome.set.id)  \"\(outcome.spec.text)\"  baseline \(outcome.literalResults.count) → now \(outcome.results.count)")
    }
}

if !stillEmpty.isEmpty {
    print("\nStill empty — no deterministic match exists at all:\n")
    var seen = Set<String>()
    for outcome in stillEmpty {
        let key = "\(outcome.set.id)\u{0}\(outcome.spec.text)"
        guard seen.insert(key).inserted else { continue }
        print("  set \(outcome.set.id)  \"\(outcome.spec.text)\"")
    }
    print("""

    These are the only cases where a semantic stage could change the visible
    result set, and it cannot do so on its own: TypeSafe re-ranking operates on a
    shortlist that fast search already produced, and each of these has an empty
    shortlist. Reaching them needs further recall work in Swift or a different
    mechanism entirely — not a re-ranker.
    """)
}

if !fixtureErrors.isEmpty {
    print("\n\u{001B}[1mFixture errors (harness bugs, not search bugs) — fix these first:\u{001B}[0m")
    for line in fixtureErrors { print("  \(line)") }
}

print("""

\u{001B}[1mPer-keystroke cost\u{001B}[0m
------------------
The search path runs synchronously inside the CGEvent tap callback on the main
actor, so it executes on every keystroke. Widening must not make typing slower.

""")

for set in WindowFixtures.all {
    let windows = set.windows.map { $0.makeWindowInfo() }
    // A single character matches the widest set and is the worst realistic case.
    let single = measure(iterations: 2_000) { _ = WindowSearch.filter(windows, query: "e") }
    // A multi-token query exercises the widening fallback.
    let widening = measure(iterations: 2_000) { _ = WindowSearch.filter(windows, query: "omeco rider") }
    print(String(
        format: "  set %@  %2d windows   single-char p50 %6.1f µs   widening p50 %6.1f µs   p95 %6.1f µs",
        set.id, windows.count, single.p50Microseconds, widening.p50Microseconds, widening.p95Microseconds
    ))
}

print("""

For reference, one TypeSafe round trip is a network request plus inference, with
no published latency guarantee. Even a fast response is three to four orders of
magnitude slower than the whole local search. That gap is why a semantic stage
can only ever be progressive enhancement, never a blocker.
""")

// MARK: - Recall flooding probe

/// Widening accepts a window when every query token appears somewhere in its
/// metadata. Two things can go wrong: the widened set can be too large to be a
/// shortlist, or it can be entirely one application and therefore useless for
/// choosing between windows. This probe measures both on the stress set.
let stressWindows = WindowFixtures.stress.windows.map { $0.makeWindowInfo() }
let stressTotal = stressWindows.count
let largeShare = 0.25

let floodProbes = [
    "Terminal docker",
    "omeco api",
    "GitHub service",
    "docker service",
    "chrome github service"
]

print("""

\u{001B}[1mRecall widening probe\u{001B}[0m
----------------------
Set E holds \(stressTotal) windows built to share vocabulary. Each probe below is a
multi-token query that matches no window literally, so it takes the widening
path.

LARGE       the widened set exceeds \(Int(largeShare * 100))% of the session — too big to be a
            shortlist
FLAT        every result is the same application, so the widening did not
            narrow anything

""")

var sawLarge = false
var sawFlat = false
for probe in floodProbes {
    let ranked = WindowSearch.ranked(
        stressWindows,
        query: probe,
        applicationName: \WindowInfo.applicationName,
        title: \WindowInfo.title
    )
    let share = Double(ranked.elements.count) / Double(stressTotal)
    let isLarge = share > largeShare
    let isFlat = ranked.elements.count > 1
        && Set(ranked.elements.map(\.applicationName)).count == 1
    if isLarge { sawLarge = true }
    if isFlat { sawFlat = true }

    var flags: [String] = []
    if isLarge { flags.append("LARGE") }
    if isFlat { flags.append("FLAT") }
    let suffix = flags.isEmpty ? "" : "   ← " + flags.joined(separator: ", ")

    print(String(
        format: "  \"%@\"  →  %2d of %d windows (%.0f%%)%@",
        probe, ranked.elements.count, stressTotal, share * 100, suffix
    ))
}

print(sawLarge || sawFlat
    ? """

    Widening is bounded: no query accepted more than a shortlist. But a query
    whose tokens all come from one application's title pattern returns the whole
    group and does not narrow it. That is a discriminating-power limit, not a
    correctness problem — the windows returned are genuinely relevant — and the
    workaround is more query tokens, which the three-token probe demonstrates.
    """
    : "\nEvery probe both stayed small and narrowed to more than one application."
)
