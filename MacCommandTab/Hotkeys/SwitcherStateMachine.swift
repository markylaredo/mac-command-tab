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
    case searchCharacter(String)
    case searchBackspace
    case searchCleared
    case cancelled
    case committed(selection: Int)
}

struct SwitcherStateMachine: Sendable {
    private(set) var selection: Int?
    private var sessionActive = false

    var isActive: Bool { sessionActive }

    mutating func handle(
        _ input: SwitcherInput,
        itemCount: Int,
        navigationLayout: SwitcherNavigationLayout = .linear,
        gridColumns: Int? = nil
    ) -> SwitcherAction? {
        if !sessionActive {
            guard itemCount > 0 else { return nil }
            guard case let .optionTab(reverse) = input else { return nil }
            let initialSelection = itemCount == 1 ? 0 : wrappedIndex(reverse ? -1 : 1, count: itemCount)
            sessionActive = true
            selection = initialSelection
            return .opened(selection: initialSelection)
        }

        guard itemCount > 0 else {
            switch input {
            case .escape, .optionReleased:
                sessionActive = false
                selection = nil
                return .cancelled
            default:
                return nil
            }
        }

        switch input {
        case let .optionTab(reverse), let .tab(reverse):
            return move(by: reverse ? -1 : 1, itemCount: itemCount)
        case .movePrevious:
            return moveHorizontally(by: -1, itemCount: itemCount, navigationLayout: navigationLayout, gridColumns: gridColumns)
        case .moveNext:
            return moveHorizontally(by: 1, itemCount: itemCount, navigationLayout: navigationLayout, gridColumns: gridColumns)
        case .moveUp:
            return moveVertically(by: -1, itemCount: itemCount, navigationLayout: navigationLayout, gridColumns: gridColumns)
        case .moveDown:
            return moveVertically(by: 1, itemCount: itemCount, navigationLayout: navigationLayout, gridColumns: gridColumns)
        case .escape:
            sessionActive = false
            selection = nil
            return .cancelled
        case .optionReleased:
            guard let selected = selection else {
                sessionActive = false
                return .cancelled
            }
            sessionActive = false
            selection = nil
            return .committed(selection: selected)
        }
    }

    mutating func reset() {
        sessionActive = false
        selection = nil
    }

    mutating func synchronizeSelection(_ index: Int?, itemCount: Int) {
        guard let index, (0..<itemCount).contains(index) else {
            selection = nil
            return
        }
        selection = index
    }

    private mutating func move(by offset: Int, itemCount: Int) -> SwitcherAction {
        let next = wrappedIndex((selection ?? 0) + offset, count: itemCount)
        selection = next
        return .selectionChanged(next)
    }

    private mutating func moveHorizontally(
        by offset: Int,
        itemCount: Int,
        navigationLayout: SwitcherNavigationLayout,
        gridColumns: Int?
    ) -> SwitcherAction? {
        guard navigationLayout == .tileGrid, let selection else {
            return move(by: offset, itemCount: itemCount)
        }

        let columns = max(1, gridColumns ?? ((itemCount + 1) / 2))
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
        navigationLayout: SwitcherNavigationLayout,
        gridColumns: Int?
    ) -> SwitcherAction? {
        guard navigationLayout == .tileGrid, let selection else {
            return move(by: rowOffset, itemCount: itemCount)
        }

        let columns = max(1, gridColumns ?? ((itemCount + 1) / 2))
        let currentColumn = selection % columns
        let targetRow = selection / columns + rowOffset
        guard targetRow >= 0 else { return nil }
        let targetRowStart = targetRow * columns
        guard targetRowStart < itemCount else { return nil }
        let targetRowEnd = min(targetRowStart + columns, itemCount) - 1
        let next = min(targetRowStart + currentColumn, targetRowEnd)
        self.selection = next
        return .selectionChanged(next)
    }

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
