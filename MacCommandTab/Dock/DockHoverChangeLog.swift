import Foundation

/// Records only when a watched value changes.
///
/// The Dock hover path runs at pointer-sample frequency, so logging each decision
/// would flood the log and change the behaviour being observed. This gates a log
/// line to state *transitions*, which is what is actually diagnostically useful:
/// "the pointer entered the Dock and no tile resolved" is a single event, not
/// thirty per second.
/// A MainActor-only helper; not `Sendable`, because it is state that is mutated
/// from pointer handling and never crosses an isolation boundary.
struct DockHoverChangeLog<Value: Equatable> {
    private var lastValue: Value?
    private var hasLogged = false

    /// True the first time, and thereafter only when `value` differs from the
    /// previous call.
    mutating func shouldLog(_ value: Value) -> Bool {
        guard !hasLogged || lastValue != value else { return false }
        hasLogged = true
        lastValue = value
        return true
    }

    mutating func reset() {
        lastValue = nil
        hasLogged = false
    }
}
