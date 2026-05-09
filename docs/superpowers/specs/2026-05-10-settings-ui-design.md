# Settings UI Design

## Goal
Improve the settings window for `用量监控` so it feels like a polished native macOS settings screen, with clear visual hierarchy and better scanability, without changing the underlying configuration model.

The settings experience should:

- stay single-column
- keep the `连接` area visually dominant
- preserve the native macOS feel
- make the primary action obvious
- keep the window readable at the existing compact size

## Scope
In scope:

- refine the settings window layout and spacing
- strengthen hierarchy between `连接`, `显示`, `刷新`, and `关于`
- improve the visual treatment of inputs, buttons, and status text
- tighten the window size and content flow so controls do not feel crowded
- keep the existing persistence and validation behavior

Out of scope:

- adding new settings categories
- changing auth or refresh logic
- introducing a sidebar or multi-pane layout
- redesigning the menu bar popover
- adding decorative illustration, gradients, or custom theming

## Layout
The window remains a single-column settings surface.

Structure:

1. A compact header at the top with the app name and one short supporting sentence.
2. `连接` as the first and strongest section.
3. `显示` as a lighter secondary section.
4. `刷新` as a tertiary section.
5. `关于` as the final low-priority section.

The layout should feel like macOS system settings: vertically ordered, easy to scan, and driven by clear section titles rather than heavy framing.

The window should be slightly taller than the current minimum so the connection block can breathe. The content should live in a scrollable container when needed rather than compressing text or controls into overlap.

## Visual System
Use the native macOS visual language:

- system background and standard control styling
- no custom gradients, noise textures, or ornamental cards
- semibold section titles, regular body text, secondary helper text
- one primary accent action only: `验证并刷新`
- secondary actions should remain visually quieter

Color should be semantic rather than decorative:

- green for success
- orange for warning
- red for failure
- secondary gray for supporting copy

Status text must always be readable as text, not only as color.

If any icon is added to a button or status label, it should use SF Symbols and stay restrained.

## Connection Section
This section carries the most visual weight.

Content order:

1. Base URL
2. API Key
3. helper text that explains the key stays local to the app
4. `验证并刷新`
5. inline validation status

The API Key input should use a secure native text field. The helper copy should sit directly under the field so the storage note is easy to find without cluttering the rest of the page.

`验证并刷新` should read as the main action in the whole window. Its state should clearly reflect when validation or refresh is in progress.

Validation feedback belongs inside this section, directly below the primary action. It should not open a modal alert for ordinary success or failure.

## Display Section
Keep this section compact and secondary.

It only needs to hold the menu bar decimal toggle, with enough spacing that it does not feel visually merged into the connection controls.

## Refresh Section
Keep the refresh controls simple and utilitarian.

It should contain:

- refresh interval picker
- `手动刷新` secondary action

The manual refresh button should be visually lighter than `验证并刷新`. It should feel like an operational control, not a second primary action.

## About Section
The about section should stay minimal.

It only needs to show the version row, aligned cleanly and pushed to the bottom of the hierarchy.

## Interaction Rules
The settings view should continue to use the existing draft-and-commit pattern:

- edits stay in local draft state until commit
- validation commits the current draft before making the request
- transient errors do not clear the user’s input
- clearing the API Key field removes the stored value
- closing the window commits the current draft

Opening the window should focus the Base URL field first.

Keyboard flow should follow the visual hierarchy: connection fields first, then validation, then the secondary controls.

## File Boundaries
Keep the implementation focused and easy to read:

- `Sources/UsageMonitor/Views/SettingsView.swift` should own the layout and section composition
- `Sources/UsageMonitor/Views/SettingsWindowController.swift` should own window sizing and focus behavior
- `Sources/UsageMonitor/Views/NativeTextInput.swift` should only change if input behavior needs to support the new layout
- `Sources/UsageMonitor/Views/SettingsDraft.swift` should remain the normalization boundary for user-entered values

If the view code starts to feel dense, split the settings sections into small private subviews rather than turning the file into one large body block.

## Testing
Add or extend tests where they provide confidence:

- keep `SettingsDraft` coverage for trimming and empty-key clearing
- keep `SettingsWindowController` coverage for activation and ordering behavior
- add tests for any new window sizing or title assumptions if they become part of the controller contract

This UI does not need pixel snapshot tests to be considered complete, but it does need manual verification in the app at the default window size and at the minimum size.

## Acceptance Criteria
The work is complete when:

- the settings window reads as a native macOS settings page
- the `连接` section is the clear focal point
- the page stays single-column and easy to scan
- labels, inputs, and helper text do not collide
- the primary action is visually obvious
- the version/about area no longer competes with the main controls
- existing persistence and validation behavior still works as before
