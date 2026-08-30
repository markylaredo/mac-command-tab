import Foundation

enum SwitcherInput: Equatable, Sendable {
    case optionTab(reverse: Bool)
    case tab(reverse: Bool)
    case movePrevious
    case moveNext
    case moveUp
    case moveDown
    case escape
    case optionReleased
}

enum SwitcherNavigationLayout: Equatable, Sendable {
    case linear
    case tileGrid
}

enum SwitcherAction: Equatable, Sendable {
    case opened(selection: Int)
    case selectionChanged(Int)
    case cancelled
    case committed(selection: Int)
}

struct SwitcherStateMachine: Sendable {
    private(set) var selection: Int?

    var isActive: Bool { selection != nil }

    mutating func handle(
        _ input: SwitcherInput,
        itemCount: Int,
        navigationLayout: SwitcherNavigationLayout = .linear
    ) -> SwitcherAction? {
        guard itemCount > 0 else {
            if isActive { selection = nil }
            return nil
        }

        if selection == nil {
            guard case let .optionTab(reverse) = input else { return nil }
            let initialSelection = itemCount == 1 ? 0 : wrappedIndex(reverse ? -1 : 1, count: itemCount)
            selection = initialSelection
            return .opened(selection: initialSelection)
        }

        switch input {
        case let .optionTab(reverse), let .tab(reverse):
            return move(by: reverse ? -1 : 1, itemCount: itemCount)
        case .movePrevious:
            return moveHorizontally(by: -1, itemCount: itemCount, navigationLayout: navigationLayout)
        case .moveNext:
            return moveHorizontally(by: 1, itemCount: itemCount, navigationLayout: navigationLayout)
        case .moveUp:
            return moveVertically(by: -1, itemCount: itemCount, navigationLayout: navigationLayout)
        case .moveDown:
            return moveVertically(by: 1, itemCount: itemCount, navigationLayout: navigationLayout)
        case .escape:
            selection = nil
            return .cancelled
        case .optionReleased:
            guard let selected = selection else { return nil }
            selection = nil
            return .committed(selection: selected)
        }
    }

    mutating func reset() {
        selection = nil
    }

    private mutating func move(by offset: Int, itemCount: Int) -> SwitcherAction {
        let next = wrappedIndex((selection ?? 0) + offset, count: itemCount)
        selection = next
        return .selectionChanged(next)
    }

    private mutating func moveHorizontally(
        by offset: Int,
        itemCount: Int,
        navigationLayout: SwitcherNavigationLayout
    ) -> SwitcherAction? {
        guard navigationLayout == .tileGrid, let selection else {
            return move(by: offset, itemCount: itemCount)
        }

        let columns = (itemCount + 1) / 2
        let rowStart = (selection / columns) * columns
        let rowEnd = min(rowStart + columns, itemCount) - 1
        let next = selection + offset
        guard next >= rowStart, next <= rowEnd else { return nil }
        self.selection = next
        return .selectionChanged(next)
    }

    private mutating func moveVertically(
        by rowOffset: Int,
        itemCount: Int,
        navigationLayout: SwitcherNavigationLayout
    ) -> SwitcherAction? {
        guard navigationLayout == .tileGrid, let selection else {
            return move(by: rowOffset, itemCount: itemCount)
        }

        let columns = (itemCount + 1) / 2
        let next = selection + rowOffset * columns
        guard (0..<itemCount).contains(next) else { return nil }
        self.selection = next
        return .selectionChanged(next)
    }

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
