import Foundation

/// What the evaluator expects for a query against a given window set.
///
/// The distinction matters more than a pass/fail bit: `.anywhere` means the
/// deterministic matcher *finds* the right window but does not put it first,
/// which is a ranking gap a semantic re-ranker could close. `.noMatch` means the
/// deterministic matcher finds nothing at all, which is a **recall** gap that a
/// re-ranker cannot close by itself — there is nothing in the shortlist to
/// reorder. Conflating the two would overstate what System One can contribute.
enum WindowSearchExpectation: Equatable {
    /// Computed by the harness from the window set under test. Used for bare
    /// application names, whose expected outcome depends on which windows the
    /// set happens to contain.
    case derived
    /// The deterministic result must place this window first.
    case top1(WindowFixture)
    /// The deterministic result must contain this window, but need not rank it first.
    case anywhere(WindowFixture)
    /// The deterministic result is expected to be empty. A semantic stage that
    /// surfaces anything here is the interesting case to evaluate.
    case noMatch
    /// An empty or whitespace-only query must return every window in the
    /// incoming order, unchanged. This is the MRU-preservation guarantee.
    case passthroughAll
}

struct QuerySpec {
    let text: String
    let expectation: WindowSearchExpectation
    /// Why this query is in the benchmark, and what a semantic win would look like.
    let note: String
    /// Restricts the query to a single window set. `nil` means it applies to
    /// every set. The "right" window for a query depends on which windows are
    /// open, so a fixture written for one set must not be graded against another.
    let setID: String?

    init(
        text: String,
        expectation: WindowSearchExpectation,
        note: String,
        setID: String? = nil
    ) {
        self.text = text
        self.expectation = expectation
        self.note = note
        self.setID = setID
    }
}

enum WindowSearchQueries {
    /// The literal, high-frequency queries a switcher must never regress on.
    ///
    /// These names appear in most of the window sets but not all of them, so the
    /// harness derives each expectation from the set under test rather than
    /// pinning one here. A bare application name must be answered by the
    /// deterministic matcher with no semantic stage involved at all.
    static let literal: [QuerySpec] = [
        QuerySpec(
            text: "Safari",
            expectation: .derived,
            note: "Bare application name. All Safari windows share rank 0; MRU order decides between them."
        ),
        QuerySpec(
            text: "Finder",
            expectation: .derived,
            note: "Bare application name. Exact app-name match, rank 0."
        ),
        QuerySpec(
            text: "Rider",
            expectation: .derived,
            note: "Bare application name. Exact app-name match, rank 0."
        ),
        QuerySpec(
            text: "term",
            expectation: .derived,
            note: "App-name prefix, rank 1. The shortest query a switcher should still handle."
        )
    ]

    /// Queries whose words appear in the metadata: partly literal, partly inferred.
    ///
    /// These are the cases where a token-level matcher is already sufficient and
    /// a semantic stage must not make things worse.
    ///
    /// If the plain token matcher described in `Benchmarks/README.md` is ever
    /// implemented, these expectations should be switched from `.noMatch` to
    /// `tokenMatch("Rider", "Omeco.ApiV2 – Rider")`.
    static let mixed: [QuerySpec] = [
        QuerySpec(
            text: "OMECO Rider",
            expectation: .noMatch,
            note: "Two tokens. \"Rider\" matches the app; \"OMECO\" matches the title as a separate token. Neither token is a substring of the other, so the full query matches nothing today — token-level matching alone would fix this, with no semantics required.",
            setID: "A"
        ),
        QuerySpec(
            text: "VS Code FleetShell",
            expectation: .noMatch,
            note: "\"VS Code\" is not a substring of \"Visual Studio Code\", and \"FleetShell\" is not a substring of \"fleet-shell\" (case and hyphen differ). Token and case folding is enough; no semantics required.",
            setID: "A"
        ),
        QuerySpec(
            text: "Chrome docs",
            expectation: .noMatch,
            note: "The word \"docs\" appears nowhere in set A. The closest window is a Safari documentation page, which shares no vocabulary with the query.",
            setID: "A"
        ),
        QuerySpec(
            text: "OMECO Rider",
            expectation: .noMatch,
            note: "Same two-token case as set A: the Rider window is present, but the full query is not a substring of any field.",
            setID: "B"
        ),
        QuerySpec(
            text: "VS Code FleetShell",
            expectation: .noMatch,
            note: "Set B contains a Visual Studio Code window, but not the fleet-shell workspace.",
            setID: "B"
        ),
        QuerySpec(
            text: "Finder downloads",
            expectation: .noMatch,
            note: "Tokens span two fields: \"Finder\" is the application, \"Downloads\" is the title. The full query matches nothing.",
            setID: "B"
        )
    ]

    /// Queries with no literal presence anywhere: the pure semantic cases.
    /// These are the only ones where a model's judgment could add anything that
    /// deterministic matching cannot already do.
    static let semantic: [QuerySpec] = [
        QuerySpec(
            text: "browser with GitHub",
            expectation: .noMatch,
            note: "Primary motivating example. \"browser\" appears in no app name or title; \"GitHub\" appears in a Chrome title. Zero local results today. A useful semantic stage would surface the Chrome GitHub window.",
            setID: "A"
        ),
        QuerySpec(
            text: "browser with GitHub",
            expectation: .noMatch,
            note: "Same query against the larger set, where three browsers are open and the Chrome GitHub window is the intended target.",
            setID: "B"
        ),
        QuerySpec(
            text: "accounting project",
            expectation: .noMatch,
            note: "Neither token appears in set A. Nothing in this set is an accounting project.",
            setID: "A"
        ),
        QuerySpec(
            text: "accounting project",
            expectation: .noMatch,
            note: "The meaning lives in Numbers, Mail, and PDF titles that share no vocabulary with the query. This is the strongest semantic case in the benchmark.",
            setID: "C"
        ),
        QuerySpec(
            text: "settings for displays",
            expectation: .noMatch,
            note: "The window is literally titled \"Displays\". A semantic stage should map the intent onto it; today the query matches nothing.",
            setID: "A"
        ),
        QuerySpec(
            text: "my terminal",
            expectation: .noMatch,
            note: "Possessive phrasing. \"terminal\" alone matches rank 0; \"my terminal\" matches nothing.",
            setID: "A"
        )
    ]

    /// Cases where a semantic stage must *lose to* deterministic matching.
    static let adversarial: [QuerySpec] = [
        QuerySpec(
            text: "Rider",
            expectation: .derived,
            note: "Must stay rank 0. A semantic stage that reorders a decisive exact-application match is a regression, not an improvement."
        ),
        QuerySpec(
            text: "Downloads",
            expectation: .derived,
            note: "A title match. Must stay ahead of any semantic candidate and must never be demoted below one."
        ),
        QuerySpec(
            text: "   ",
            expectation: .passthroughAll,
            note: "Whitespace-only query is normalised to empty and must return every window unchanged, in the incoming MRU order."
        )
    ]

    /// Queries whose expected window is genuinely absent from the window set.
    /// These are control cases: the correct answer is "no results", and they
    /// guard against the harness counting a hallucinated match as a win.
    ///
    /// `.noMatch` is only a valid expectation when no window in the set matches
    /// the query literally. The harness enforces that rule and rejects any
    /// fixture that violates it.
    static let absent: [QuerySpec] = [
        QuerySpec(
            text: "Rider",
            expectation: .noMatch,
            note: "Control. This window set contains no Rider window.",
            setID: "C"
        ),
        QuerySpec(
            text: "Downloads",
            expectation: .noMatch,
            note: "Control. This window set contains no window titled Downloads.",
            setID: "C"
        )
    ]

    /// Every query defined in this file, regardless of which set it applies to.
    /// The harness validates all of them; only the applicable ones are graded.
    static let all: [QuerySpec] = literal + mixed + semantic + adversarial + absent
}
