# GlobeSwitch

GlobeSwitch is a native macOS menu-bar app that cycles directly through the enabled
input sources selected in its menu. It supports two or more keyboard layouts or
input methods, including regional variants such as British English.

It uses a listen-only Core Graphics event tap and calls Apple's Text Input Sources API
synchronously on the **Globe/Fn key-down** event. There is no language HUD, animation,
mouse interaction, synthetic switching shortcut, shell process, or intentional delay in language switching.
The menu-bar indicator uses the same 22-by-16-point dynamic input-source image that
macOS generates for its own Input menu, such as `A` or `УК`. The image is loaded at
runtime and cached; if the private system renderer is unavailable after a macOS
update, GlobeSwitch falls back to the compact fixed-width `:EN`/`:UA` label.

## Required macOS setup

1. Open **System Settings → Keyboard**.
2. Set **Press Globe key to** to **Do Nothing**.
3. Launch GlobeSwitch and choose **Request Keyboard Access…** from its menu-bar menu.
4. Enable the app in the privacy pane macOS opens, then relaunch it if required.
5. In **Input Sources in Globe Cycle**, check the sources that Globe should cycle through.

At least two sources must remain selected. The selection persists across launches and
follows the source order reported by macOS. If the current source is outside the
selection, the next Globe press moves to the first selected source.

**Input Monitoring** is required for Globe-key detection. **Accessibility** is
also required for selected-text correction; grant it to GlobeSwitch in
**System Settings → Privacy & Security → Device Control and Data Access**
(on older macOS versions, **Accessibility**). Without Accessibility,
Globe continues to switch layouts but cannot inspect or correct selected text.

The system setting is important: leaving it on **Change Input Source** makes the native
handler and GlobeSwitch both react to the same key.

## Correct selected text with Globe

- **No selection:** Globe switches to the next input source on key-down.
- **Selected editable text:** Globe converts the entire selection to the **next
  input source in the configured cycle**, replaces it, then selects that source.
- The menu item **Correct Selected Text & Switch** runs the same correction.
  There is no separate correction hotkey.

For example, with Ukrainian active, select `руддщ` and press Globe: it becomes
`hello` and ABC becomes active. With ABC active, select `ghbdsn`: it becomes
`привіт` and Ukrainian becomes active. The destination always follows the cycle;
it is not inferred from the text. If you already manually changed layouts, the
next cycle entry still determines the destination.

Conversion currently supports **ABC ↔ Ukrainian-PC**. It reads macOS's actual
key-layout data for normal and Shift key states, including punctuation. Characters
absent from the source map (such as emoji and target-language letters) are retained.
This is physical-key correction, not translation, spelling correction, or phonetic
transliteration. Option/dead-key sequences and smart punctuation cannot always be
reconstructed from their resulting text. Duplicate key outputs use the primary key.
If the next cycle entry is another layout, correction reports an unsupported-layout
message and leaves the text and layout unchanged.

Correction checks the focused editable field via Accessibility. After Globe and
modifiers are released, it uses the field's normal Paste operation so the host app
can supply its usual **Command-Z** undo. A copy fallback is used only when macOS
reports a nonempty selection but cannot return its text. Clipboard formats are
restored afterward unless another clipboard update occurred. Text is processed
locally and is never logged or sent to a model.

Focus and selection are rechecked before replacement. Replacement is verified via
the field's value or caret position before switching layouts; an unverified paste
is never retried automatically. Password fields and Secure Input are excluded.
Some custom or inaccessible fields do not expose a selection and therefore fall
back to ordinary switching. If a field accepts Paste but does not expose enough
information to verify it, the text may change while the layout stays unchanged;
a beep and a menu error explain this. Universal support for all custom controls
cannot be guaranteed.

When **Correct Selected Text & Switch** is disabled, the menu now explains whether
correction is busy, permission is missing, Secure Input is active, the focused
field is unavailable, no selection is exposed, or the selected element is not
editable. These messages do not include selected text. Selection capture checks
both direct text and text-marker text, even when the numeric range is collapsed.
Conflicting numeric ranges are not used to calculate the expected replacement.

The user reported on 2026-09-17 that correction works in Messages but is disabled
in both ChatGPT Work editors. A subsequent user screenshot showed error `-25212`
(`kAXErrorNoValue`) while reading `AXFocusedUIElement`, before reading selection.
The selection fallback changes therefore did not resolve the observed blocker.
When the app exposes no focused field, GlobeSwitch makes one activation attempt
per app launch, first using Electron's
[`AXManualAccessibility`](https://www.electronjs.org/docs/latest/tutorial/accessibility).
The user's next screenshot showed `-25205` (`kAXErrorAttributeUnsupported`) for
that request. The installed framework contains `AXEnhancedUserInterface` but no
`AXManualAccessibility` string. GlobeSwitch now falls back to
`AXEnhancedUserInterface` only when the manual attribute is explicitly unsupported.
[Chromium's implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm)
uses a two-second debounce before enabling full accessibility support, so allow
about three seconds after the first request before retesting. This timing comes
from upstream source, not a measurement of the installed app.
GlobeSwitch never disables these flags. If the renderer is not ready immediately, the menu
asks the user to select the text and retry; that initial Globe press does not
switch layouts. No background UI traversal or text logging is added.
Selection evidence and activation negotiation are covered by 17 passing unit
tests. On 2026-09-17, after adding the Chromium fallback, the user confirmed that
correction works in ChatGPT Work. The app log also recorded three completed
corrections at 18:10:22, 18:10:24, and 18:10:30 UTC. Those log entries do not
identify the host editor; separate coverage of both ChatGPT editors and behavior
after restarting ChatGPT have not yet been independently verified.

Version 0.3.2 (build 10) includes these compatibility changes.

## Deliberate trade-off

GlobeSwitch optimizes for typing speed by switching on key-down, not key-up. Globe/Fn
is therefore treated as a dedicated language key. Using it as a modifier can also
change the language. Quit or pause GlobeSwitch before relying on Globe/Fn shortcuts.

## Build and run

```bash
./script/build_and_run.sh
```

Verification:

```bash
swift test
./script/build_and_run.sh --verify
```

The staged bundle is `dist/GlobeSwitch.app`.

The selected Fold artwork lives in `Resources/IconDesign/Fold-original.png`.
Run `./script/build_icon.sh` to regenerate `Resources/AppIcon-1024.png` and
`Resources/AppIcon.icns` at all standard macOS sizes.

## Personal installer

Build the Apple Silicon release app and DMG installer:

```bash
./script/package_release.sh
```

The script performs a release build, stages a hardened-runtime ad-hoc signed app,
validates its bundle identifier and architecture, creates and verifies a compressed
DMG, and writes SHA-256 checksums. Release artifacts are kept in Git so the last
known-good installer can be restored without Xcode:

```text
release/
├── GlobeSwitch.app
├── GlobeSwitch-0.3.2-arm64.dmg
└── SHA256SUMS.txt
```

The DMG includes an Applications shortcut and Ukrainian installation instructions.
It is intended for direct testing on Apple Silicon Macs and is not Apple-notarized.

The measurements, design trade-offs, alternatives, and current verification state
are recorded in [`INVESTIGATION_2026-08-17.md`](INVESTIGATION_2026-08-17.md).

## Permissions and local signing

The app needs Input Monitoring permission for its listen-only event tap. The local
bundle is ad-hoc signed because this Mac currently has no Developer ID or Apple
Development code-signing identity. Its explicit designated requirement is stable
across local builds so macOS can retain the permission for this bundle identifier.

## Permission switch is on but correction does not work

A visible enabled switch does not prove the running executable is trusted. In the
2026-09-15 investigation, macOS TCC logged `Failed to match existing code requirement`
for GlobeSwitch: the stored Accessibility approval referenced an older code hash.
The installed app consequently reported `AXIsProcessTrusted() == false`.

Repair the app-specific permission record through System Settings and select the
current `/Applications/GlobeSwitch.app`; toggling the stale entry alone may not
refresh its code requirement. Recheck the app's startup diagnostics after restart.
Do not change any other application's permission or edit the TCC database.

## GitHub releases

The tag-triggered `.github/workflows/release.yml` checks the version and committed
installer checksums, then publishes the DMG and a download-only `SHA256SUMS.txt`.
Add matching `release-notes/vX.Y.Z.md`, run the local release packager, commit the
verified artifacts, and push the matching `vX.Y.Z` tag. The workflow uploads to a
draft first and publishes only after the assets have uploaded.
