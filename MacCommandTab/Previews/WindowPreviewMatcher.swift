import CoreGraphics
import Foundation

struct WindowPreviewTarget: Sendable {
    let id: WindowID
    let pid: pid_t
    let title: String
    let frame: CGRect

    init(window: WindowInfo) {
        id = window.id
        pid = window.pid
        title = window.title
        frame = window.frame
    }

    init(id: WindowID, pid: pid_t, title: String, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
    }
}

struct WindowPreviewCandidate: Equatable, Sendable {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
}

struct WindowPreviewMatcher: Sendable {
    func match(target: WindowPreviewTarget, candidates: [WindowPreviewCandidate]) -> WindowPreviewCandidate? {
        let sameProcess = candidates.filter { $0.pid == target.pid }
        guard !sameProcess.isEmpty else { return nil }
        if sameProcess.count == 1 { return sameProcess[0] }

        let targetTitle = normalized(target.title)
        let scored = sameProcess.map { candidate in
            let candidateTitle = normalized(candidate.title)
            let titleScore: CGFloat
            if !targetTitle.isEmpty, candidateTitle == targetTitle {
                titleScore = 10_000
            } else if !targetTitle.isEmpty,
                      (candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle)) {
                titleScore = 2_500
            } else {
                titleScore = 0
            }
            return (candidate, titleScore + frameScore(target.frame, candidate.frame))
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    private func normalized(_ title: String) -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "untitled window" ? "" : value
    }

    private func frameScore(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let distance = abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
        return max(0, 2_000 - distance)
    }
}
