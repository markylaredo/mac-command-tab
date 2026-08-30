import Foundation

struct WindowFrameCache: Sendable {
    private let capacity: Int
    private var snapshots: [WindowID: WindowSnapshot] = [:]
    private var usageOrder: [WindowID] = []

    init(capacity: Int = 12) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { snapshots.count }

    mutating func insert(_ snapshot: WindowSnapshot) {
        usageOrder.removeAll { $0 == snapshot.windowID }
        snapshots[snapshot.windowID] = snapshot
        usageOrder.append(snapshot.windowID)

        while usageOrder.count > capacity {
            snapshots.removeValue(forKey: usageOrder.removeFirst())
        }
    }

    mutating func snapshot(for windowID: WindowID) -> WindowSnapshot? {
        guard let snapshot = snapshots[windowID] else { return nil }
        usageOrder.removeAll { $0 == windowID }
        usageOrder.append(windowID)
        return snapshot
    }

    mutating func snapshots(for windowIDs: Set<WindowID>) -> [WindowID: WindowSnapshot] {
        var result: [WindowID: WindowSnapshot] = [:]
        for windowID in windowIDs {
            if let snapshot = snapshot(for: windowID) {
                result[windowID] = snapshot
            }
        }
        return result
    }

    mutating func removeAll() {
        snapshots.removeAll(keepingCapacity: true)
        usageOrder.removeAll(keepingCapacity: true)
    }
}
