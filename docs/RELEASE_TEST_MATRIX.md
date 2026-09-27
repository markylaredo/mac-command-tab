# Release test matrix

Record the macOS version, Mac model, build number, display arrangement, and result for each tested configuration. Use **Pass**, **Fail**, or **Not applicable**, with a short note for failures.

## Permissions

- [ ] First launch with Accessibility denied explains why switching needs access and offers one clear action.
- [ ] Granting Accessibility updates Settings without restarting and enables the shortcut.
- [ ] Revoking Accessibility while running cancels an open switcher safely and disables switching.
- [ ] Screen Recording denied leaves switching usable and shows a stable preview placeholder.
- [ ] Granting Screen Recording updates Settings without restarting where supported by macOS.
- [ ] An ad-hoc Debug rebuild is identified as “MacCommandTab Dev” and offers relaunch/stale-entry repair instead of showing an unexplained denial.
- [ ] Revoking Screen Recording while running tears down preview work without affecting activation.
- [ ] Permission copy says previews are shown inside the switcher and does not imply continuous recording.

## Switcher

- [ ] 0 eligible windows shows the compact “No windows available” state.
- [ ] 1 window has a readable preview and clear selection.
- [ ] 2–4 windows use larger, balanced cards without excess panel space.
- [ ] 8 windows remain readable with consistent gutters.
- [ ] 15+ windows use a compact grid and controlled vertical scrolling.
- [ ] Tab, Shift-Tab, and arrow-key navigation select predictably.
- [ ] Pointer hover changes selection only after intentional movement; click commits.
- [ ] Typing filters by application and title; after typing starts, Option can be released and search remains active.
- [ ] Enter commits the selected result; Escape clears search, then cancels.
- [ ] Cancel restores the originally focused window; commit activates the chosen window.
- [ ] The selected card is identifiable in under one second in light, dark, and colorful backgrounds.

## Preview

- [ ] Thumbnail mode opens quickly, captures sequentially, and refreshes stale visible content.
- [ ] Live Preview visibly updates the selected window and gives it the highest refresh priority.
- [ ] Rapid selection changes preserve the last valid frame until the next frame is ready.
- [ ] Repeated open/cancel/open cycles do not leak streams or accept stale callbacks.
- [ ] Closing a previewed window removes only that window and keeps the session usable.
- [ ] Minimized, hidden, protected, and full-screen windows show a sensible fallback where capture is unavailable.
- [ ] Portrait, ultrawide, and standard windows preserve aspect ratio without stretching.

## Dock hover previews

- [ ] Small, Medium, and Large thumbnail sizes persist after relaunch and apply on the next hover.
- [ ] Groups with 4, 10, and 20 windows progressively shrink; overflow remains reachable by scrolling.
- [ ] On a narrow display, columns reduce without clipping cards horizontally.
- [ ] Hovering a card briefly brings its real window forward; the popup stays visible and cards do not reorder.
- [ ] Leaving the popup restores the original window; clicking a card commits without restoring it.
- [ ] Rapid card-to-card movement and closing a hovered window do not activate a stale window.
- [ ] Turning off “Show the real window on hover” keeps hover limited to the card highlight.
- [ ] Hovering minimized, hidden, or full-screen windows does not restore them or switch Spaces; clicking still activates them.

Requires Accessibility access. Record the macOS version and Dock configuration for
each run: Dock application resolution depends on the Dock's accessibility
hierarchy, which is not public API and can differ between releases.

- [ ] Hovering an application's Dock icon for roughly 300 ms shows previews of that application's windows only.
- [ ] Each card shows the correct window with its title.
- [ ] Clicking a card activates that exact window.
- [ ] A minimized window can be restored from its card.
- [ ] The pointer can travel from the Dock icon into the popup without the popup disappearing.
- [ ] Moving directly to another Dock app swaps the previews without leaving stale cards.
- [ ] Leaving both the Dock and the popup dismisses it after the grace period.
- [ ] Hovering the Trash, a folder, or a minimized-window tile shows nothing.
- [ ] An application with a single window still shows its preview.
- [ ] An application with no switchable windows shows no popup at all.
- [ ] The popup is anchored to the hovered icon and stays fully on screen, for bottom, left, and right Dock positions.
- [ ] With two displays, the popup appears on the display holding the Dock icon.
- [ ] Thumbnail mode shows static previews; Live Preview mode shows live ones.
- [ ] Live previews stop after dismissal. Confirm from the PreviewSession log that no stream remains active.
- [ ] The close button appears only while hovering a card, closes that window, and does not quit the application.
- [ ] Closing the last window dismisses the popup.
- [ ] Opening the Option–Tab switcher while a Dock preview is visible dismisses the Dock preview, and the switcher behaves normally.
- [ ] Turning the feature off in Settings stops all Dock preview activity immediately.
- [ ] Revoking Accessibility while the feature is enabled dismisses any popup and leaves the switcher working.

## Displays and accessibility

- [ ] Single Retina display.
- [ ] Single non-Retina display where available.
- [ ] Two displays with the same scale.
- [ ] Mixed Retina/non-Retina or mixed scaling.
- [ ] Switcher opens on the display containing the pointer.
- [ ] Disconnecting or changing a display closes the active session safely and recalculates on reopen.
- [ ] Reduce Motion replaces scale/position transitions with immediate opacity/color changes.
- [ ] Reduce Transparency remains readable.
- [ ] Increase Contrast keeps panel boundaries and selected state visible.
- [ ] VoiceOver announces application, window title, and selected state.

## Lifecycle and release identity

- [ ] Launch starts quietly in the menu bar without opening Settings or automatically requesting permissions.
- [ ] Opening Settings from the menu bar or reopening the app shows General, Previews, and Permissions tabs.
- [ ] All settings remain reachable by scrolling on a small screen and via keyboard navigation.

- [ ] Launch at Login enables, disables, and reports approval-required state correctly.
- [ ] Quit tears down previews and leaves no MacCommandTab process.
- [ ] Relaunch restores saved preview and appearance preferences.
- [ ] Sleep/wake preserves shortcut operation and does not leave stale previews.
- [ ] The signed app passes `codesign`, `stapler`, and `spctl` validation.
- [ ] The running production process path is `/Applications/MacCommandTab.app/Contents/MacOS/MacCommandTab`.
- [ ] Xcode's Debug build appears as “MacCommandTab Dev” and does not replace the release app.
