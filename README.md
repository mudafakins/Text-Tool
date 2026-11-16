# Text Tool

A lightweight, native macOS menu bar app that makes your clipboard smart. All processing is 100% on-device.

- **Case conversion**: copy text, click the menu bar icon (**Aa**), then pick `UPPERCASE`, `lowercase`, `Title Case`, `Sentence case`, `camelCase` or `snake_case`. The preview updates and the result is copied to your clipboard right away. **Original** (⌘0) restores the original text. Shortcuts: ⌘1–⌘6.
- **Clipboard OCR**: copy a screenshot (⌘⇧⌃4), an image from a browser or Preview, or an image file in Finder, then click the icon. Text Tool recognizes the text with Apple Vision, shows it in the preview, and replaces the image on the clipboard with the text. You can turn this off in ⚙︎ › "Replace copied images with text". Case buttons work on the recognized text too.
- **Drop & paste**: drag an image, an image file, a text file or text onto the menu bar icon or into the open popover, or press ⌘V in the popover to take what's on the clipboard. Images are converted to text; the result is added to history and copied to the clipboard.
- **History**: ‹ › (⌘[ ⌘]) step through the last 10 items. Kept in memory only; items marked private by password managers are skipped.
- **Settings** (⚙︎): check for updates, automatic update checks, launch at login, image replacement, About, quit.
- **Updates**: Text Tool checks for a new version once a day (and on demand from ⚙︎ › Check for Updates…). When one is out, an **Update** banner appears in the popover; it downloads, verifies and relaunches into the new version.

Conversions always start from the original text, so you can switch between cases without losing anything. Title and sentence case keep acronyms and mixed-case words (NASA, iPhone, macOS) unless the whole text is in caps.

## Build

Requires macOS 14+ and Xcode (or the Swift toolchain).

```bash
./build.sh            # builds "build/Text Tool.app"
./build.sh --install  # also copies it to /Applications and launches it
swift test            # unit tests for case conversion and OCR
```

The very first OCR on a Mac can take up to a minute while macOS prepares its Vision models. After that it takes a fraction of a second.

## Install

Download the newest zip from [`releases/`](releases), unzip it, and move **Text Tool.app** to your Applications folder. From then on the app updates itself.

## Versions, releases and going back

Every published version is kept:

- `releases/TextTool-<version>.zip`: the built app for each version
- git tag `v<version>`: the exact source code for that version
- `CHANGELOG.md`: what changed in each version
- `updates/latest.json`: the version installed apps update to

**Publishing a version** (commit your changes first):

```bash
./release.sh 1.1.0 "Short description of what changed" --push
```

**Going back to an earlier version**

- *Just the app:* download an older zip from `releases/` and replace the app in Applications.
- *Everyone's app:* to roll every installed copy back, check out the old code and publish it under a new, higher version number (installed apps only move forward):

  ```bash
  git checkout v1.0.0 -- Sources Resources
  git commit -m "Revert to 1.0.0 behaviour"
  ./release.sh 1.0.2 "Reverts the changes from 1.0.1" --push
  ```

- *Look at or build old code:* `git checkout v1.0.0`, then `./build.sh` (and `git switch main` to come back).

## Layout

- `Sources/TextToolCore`: `CaseConverter` (all conversions) and `TextRecognizer` (Vision OCR)
- `Sources/TextTool`: menu bar item, popover UI (`PopoverView`), clipboard logic (`ClipboardModel`)
- `Sources/TextTool/Updater.swift`: self-updater that reads `updates/latest.json`, verifies the zip's SHA-256 and code signature, and swaps the app in place
- `Resources`: `Info.plist` (`LSUIElement`, so no Dock icon) and the app icon (`scripts/make_icon.swift` regenerates it)
