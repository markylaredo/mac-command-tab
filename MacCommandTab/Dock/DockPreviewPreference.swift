import Foundation

/// Preferences for the Dock hover previews.
///
/// Follows the existing preference-enum pattern in `SwitcherView`. The preview
/// mode itself is deliberately not duplicated here: the feature reuses the user's
/// existing Thumbnail / Live Preview setting.
enum DockPreviewPreference {
    static let thumbnailWidthKey = "dockPreviewThumbnailWidth"
    static let focusOnHoverKey = "dockPreviewFocusOnHover"
    static let thumbnailWidthRange = 160...320
    static let defaultThumbnailWidth = 240

    static var thumbnailWidth: Int {
        let value = UserDefaults.standard.object(forKey: thumbnailWidthKey) as? Int ?? defaultThumbnailWidth
        return min(thumbnailWidthRange.upperBound, max(thumbnailWidthRange.lowerBound, value))
    }

    static func save(thumbnailWidth: Int) {
        UserDefaults.standard.set(min(thumbnailWidthRange.upperBound, max(thumbnailWidthRange.lowerBound, thumbnailWidth)), forKey: thumbnailWidthKey)
    }

    static var focusOnHover: Bool {
        UserDefaults.standard.object(forKey: focusOnHoverKey) as? Bool ?? true
    }

    static func save(focusOnHover: Bool) {
        UserDefaults.standard.set(focusOnHover, forKey: focusOnHoverKey)
    }

    static let enabledKey = "dockPreviewEnabled"
    static let hoverDelayKey = "dockPreviewHoverDelayMilliseconds"

    static let defaultHoverDelayMilliseconds = 300

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) != nil else { return true }
        return defaults.bool(forKey: enabledKey)
    }

    static func save(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static var hoverDelayMilliseconds: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: hoverDelayKey) != nil else {
            return defaultHoverDelayMilliseconds
        }
        return DockHoverStateMachine.clampedHoverDelay(
            milliseconds: defaults.integer(forKey: hoverDelayKey)
        )
    }

    static func save(hoverDelayMilliseconds: Int) {
        UserDefaults.standard.set(
            DockHoverStateMachine.clampedHoverDelay(milliseconds: hoverDelayMilliseconds),
            forKey: hoverDelayKey
        )
    }

    static var hoverDelay: Duration {
        .milliseconds(hoverDelayMilliseconds)
    }
}
