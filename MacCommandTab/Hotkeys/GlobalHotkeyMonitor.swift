@preconcurrency import ApplicationServices
import AppKit
import Foundation

@MainActor
final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = SwitcherStateMachine()
    private var itemCount = 0
    private var navigationLayout = SwitcherNavigationLayout.linear
    private var navigationColumns: Int?
    private var searchQueryIsEmpty = true
    private var swallowedKeyCodes: Set<CGKeyCode> = []
    var onAction: ((SwitcherAction) -> Void)?

    var isRunning: Bool { eventTap != nil }
    var selectedIndex: Int? { stateMachine.selection }

    func updateItemCount(_ count: Int) {
        itemCount = count
        if count == 0 { stateMachine.reset() }
    }

    func updateNavigationLayout(_ layout: SwitcherNavigationLayout) {
        navigationLayout = layout
    }

    func updateActiveSession(
        itemCount: Int,
        selectedIndex: Int?,
        columns: Int,
        queryIsEmpty: Bool
    ) {
        self.itemCount = itemCount
        navigationLayout = .tileGrid
        navigationColumns = max(1, columns)
        searchQueryIsEmpty = queryIsEmpty
        stateMachine.synchronizeSelection(selectedIndex, itemCount: itemCount)
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        stateMachine.reset()
        swallowedKeyCodes.removeAll()
        navigationColumns = nil
        searchQueryIsEmpty = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hasConflictingModifiers = !flags.intersection([.maskCommand, .maskControl]).isEmpty

        if type == .keyUp, swallowedKeyCodes.remove(keyCode) != nil {
            return nil
        }

        let input: SwitcherInput?
        var directAction: SwitcherAction?
        var shouldSuppress = false
        switch (type, keyCode) {
        case (.keyDown, 48) where flags.contains(.maskAlternate) && !hasConflictingModifiers:
            let reverse = flags.contains(.maskShift)
            input = stateMachine.isActive ? .tab(reverse: reverse) : .optionTab(reverse: reverse)
            shouldSuppress = true
        case (.keyDown, 123) where stateMachine.isActive:
            input = .movePrevious
            shouldSuppress = true
        case (.keyDown, 124) where stateMachine.isActive:
            input = .moveNext
            shouldSuppress = true
        case (.keyDown, 126) where stateMachine.isActive:
            input = .moveUp
            shouldSuppress = true
        case (.keyDown, 125) where stateMachine.isActive:
            input = .moveDown
            shouldSuppress = true
        case (.keyDown, 51) where stateMachine.isActive:
            input = nil
            directAction = .searchBackspace
            shouldSuppress = true
        case (.keyDown, 53) where stateMachine.isActive && !searchQueryIsEmpty:
            input = nil
            directAction = .searchCleared
            shouldSuppress = true
        case (.keyDown, 53) where stateMachine.isActive:
            input = .escape
            shouldSuppress = true
        case (.flagsChanged, _) where stateMachine.isActive && !flags.contains(.maskAlternate):
            input = .optionReleased
        default:
            input = nil
            if type == .keyDown,
               stateMachine.isActive,
               !hasConflictingModifiers,
               let characters = printableCharacters(from: event) {
                directAction = .searchCharacter(characters)
                shouldSuppress = true
            }
        }

        if shouldSuppress { swallowedKeyCodes.insert(keyCode) }
        if let directAction { onAction?(directAction) }
        if let input, let action = stateMachine.handle(
            input,
            itemCount: itemCount,
            navigationLayout: navigationLayout,
            gridColumns: navigationColumns
        ) {
            onAction?(action)
        }
        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    private func printableCharacters(from event: CGEvent) -> String? {
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return characters
    }
}
