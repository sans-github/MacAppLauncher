# CLAUDE.md

## Build

Built via GitHub Actions on push to main (Xcode 15.2, Swift 5.9). Install locally with
`scripts/create-signing-cert.sh` (once), then `scripts/install-latest.sh` after each green build.
There is no full Xcode locally; `swiftc -typecheck -parse-as-library -target arm64-apple-macos14.0 MacAppLauncher/*.swift`
is the only local check, and it will not catch Swift 5.9-only errors (see ../MacRecordWidget/CLAUDE.md).

## Architecture

One file, `MacAppLauncher/MacAppLauncherApp.swift`:

- `AppCatalog` scans the projects folder (default `~/Documents/hello-claude/mac-widgets`, changeable from the
  folder button, stored in UserDefaults `projectsRoot`). Each sibling folder with an `.xcodeproj` becomes one
  entry, named after the project, not the folder (`MacSoshinWidgets` builds `Shoshin.app`). This app is excluded.
- Entries resolve to `/Applications/<name>.app` or `~/Applications/<name>.app`; uninstalled projects are hidden.
- Icons come from the repo (`<folder>/<project>/*.xcassets/AppIcon.appiconset`, largest PNG), then the installed
  bundle (read directly, since NSWorkspace returns the tinted rendition), then a gray initial tile.
- Running state comes from `NSWorkspace` launch/terminate notifications, keyed by bundle ID.
- Quit uses `NSRunningApplication.terminate()` (polite quit; the app may still prompt to save).
- Styles (`RowPalette`, `CapsuleControlButtonStyle`) are a trimmed copy of MacRecordWidget's: #007AFF lit
  capsule for on, bordered rounded rect for off, 0.35 opacity when disabled.

Adding a source file requires four `project.pbxproj` edits by hand, as in MacRecordWidget.
