# Globe selection correction — 2026-09-15

## Implemented contract

The existing Globe/Fn key uses the next entry in the selected source cycle.
Without an accessible editable selection it switches normally. With a selection,
it converts all mapped characters to that next layout, replaces the selection,
and changes the input source after verifying replacement. There is no additional
hotkey. The menu has an equivalent correction command.

Conversion supports ABC and Ukrainian-PC and uses installed macOS key-layout data.
Clipboard handling preserves formats where data is available and never restores over
a subsequent clipboard change. Focus and selection are rechecked, and no text is
logged. Normal Paste is used so host applications retain their standard undo path.

## Verified

- `swift test`: 9 tests pass, including existing Globe down/up behavior and source
  cycle selection, plus conversion in both directions, uppercase, keyboard
  punctuation, multiline whitespace, emoji, and explicit destination behavior.
- Debug build and bundle launch through `script/build_and_run.sh --verify` pass.
- Release build, bundle signature, and DMG verification pass.
- Installed `/Applications/GlobeSwitch.app` reports 0.3.0; its executable SHA-256
  matches the release app.
- Launch diagnostics report the Globe event monitor active and the current cycle
  as ABC, Ukrainian-PC.
- Launch at login already points to `/Applications/GlobeSwitch.app`.

## Pending hardware/UI verification

The user reported enabling Accessibility. However, a fresh restart of the final
installed app at 18:01:43 UTC still logged `accessibility=false`; Input Monitoring
was true. The installed Accessibility entry needs to be toggled or re-added for
`/Applications/GlobeSwitch.app`. Ordinary switching remains available.

TextEdit UI access recovered and a disposable test document was populated with
`Before руддщ after`, with only `руддщ` selected. The automation tool cannot generate
Fn (`keyNotFound("Fn")`) and menu-bar app inspection timed out. No real-field
replacement, clipboard restoration, or host undo result is claimed as tested.

After granting Accessibility, check:

1. Ukrainian active: select only `руддщ`, press and release Globe; expect `hello`
   and ABC active. Surrounding unselected text must remain unchanged.
2. ABC active: select `ghbdsn`, press Globe; expect `привіт` and Ukrainian active.
3. No selection: Globe switches once on key-down, including repeated presses.
4. Use the menu correction on a selection in another app.
5. Verify Command-Z restores text and the preexisting clipboard remains available.
6. Change focus while holding Globe: the pending correction should abort.

Custom controls without accessible selection information fall back to switching.
If Paste cannot be verified through the value or caret, report the failure and do
not retry or change the layout. Secure Input and password fields are excluded.

## Local rollback

The previous installed 0.2.5 app is preserved at
`.local-backups/2026-09-15-before-0.3.0/GlobeSwitch.app` (ignored by Git).
The previous 0.2.5 DMG remains in `release/`.

## Icon update — 0.3.1

The user selected option 2 (Fold). Its original generated PNG and prompt are
preserved in `Resources/IconDesign/`. `script/build_icon.sh` produces the 10
standard ICNS representations from 16 to 1024 px. Extracted 32 px and 128 px
representations were visually inspected. Native `iconutil` packaging required
execution outside the filesystem sandbox; the resulting icon round-trip passed.

The 0.3.1 release build, signature, and DMG verification passed. The installed app
reports 0.3.1, and the installed `AppIcon.icns` SHA-256 matches the source asset.
The prior installed app was backed up in
`.local-backups/2026-09-15-before-fold-icon/GlobeSwitch.app`.

## Accessibility repair — 18:22 UTC

The user reported that selection correction did not run. The UI switch was on,
but TCC logs showed `Failed to match existing code requirement` for Accessibility:
a stored `cdhash 77bea6628962361151a4e25157195d9df7fb0244` did not match the installed
0.3.1 app (`4ca474ba21df0c92c58dfbb5e364b9e3a965d3a6`).

The installed app is ad-hoc signed with explicit designated requirement
`identifier "com.alexd.sound.GlobeSwitch"`. No missing private entitlement was
added and the TCC database was not edited.

Repair: reset only `Accessibility com.alexd.sound.GlobeSwitch` with `tccutil`,
then use System Settings → Privacy & Security → Device Control and Data Access →
Add, authenticate with the user's Touch ID, and select exactly
`/Applications/GlobeSwitch.app`. After restart at 18:22:21 UTC, diagnostics reported
`accessibility=true` and `inputMonitoring=true`. This supersedes the earlier
permission-blocked status. No executable changes were needed for this repair.

Evidence: `evidence/globeswitch-tcc-2026-09-15.txt` and
`evidence/globeswitch-tcc-after-repair-2026-09-15.txt`.

## User acceptance

After the Accessibility repair, the user explicitly reported testing the feature
and confirmed that everything works, then requested publication of the installer
and GitHub release. This is user-confirmed physical-key behavior; it does not
establish universal compatibility with every custom input control.

Raw TCC diagnostic files remain local and are excluded from Git.
