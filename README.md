# CutoutDropZone

Drop a photo and get back a transparent-background cutout of its subject in seconds, fully offline.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Latest release](https://img.shields.io/github/v/release/turhe123/cutout-drop-zone)

## Why

CutoutDropZone is a free, open-source, 100% native, backend-free alternative to paid utilities in the *Files & Conversion* category. It was inspired by Droply ($9 one-time), a native offline background remover. Web-based tools upload your photos and often charge per image. This app does the work on your Mac with Apple's Vision framework, so your images never leave the machine.

## Features

- **Drop zone**: drag in one or many images (PNG, JPEG, HEIC, TIFF), or click the zone or use **Add Files** (⌘O). Folders are expanded to the images they contain. The Dock icon also accepts dropped images.
- **Subject lifting with Vision**: uses `VNGenerateForegroundInstanceMaskRequest` and composites the result with Core Image.
- **Batch queue**: images are processed one after another in the background, with a progress bar and a per-image status. Unsupported or corrupted files get a short error row and the batch continues.
- **Before / after preview** on a checkerboard, toggled with the Space bar.
- **Multiple subjects**: when several subjects are detected, click one in the preview to include or exclude it. At least one stays selected.
- **Per-image controls**: background (transparent, white, black or a custom color), edge feather from 0 to 5 px, and trim to subject bounds.
- **Export**: PNG with transparency, or JPEG (quality 0.92) on an opaque background. JPEG with a transparent background is flattened onto white.
- **Export All** to a folder with a file name suffix (default `-cutout`). Originals are never overwritten, and a counter is added if the name is taken.
- **Copy** the selected cutout to the clipboard (PNG and TIFF).
- **Drag out** a cutout from the list or preview into Finder or other apps.
- **No subject found?** The item gets a warning badge and the original is kept.
- **Large images** are downscaled for the model and the mask is scaled back up. EXIF orientation is applied.
- **Settings**: default format, output folder, file name suffix, default background, feather, and trim.

## Screenshots

_Screenshots coming soon._

## Install

1. Download `CutoutDropZone-macOS.zip` from the [latest release](https://github.com/turhe123/cutout-drop-zone/releases/latest).
2. Unzip it and move `CutoutDropZone.app` to `/Applications`.
3. Because the app is open source and not notarized, clear the quarantine flag:

   ```bash
   xattr -cr /Applications/CutoutDropZone.app
   ```

4. Right-click the app and choose **Open** the first time.

Requires macOS 14 or later.

## Build from source

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project CutoutDropZone.xcodeproj -scheme CutoutDropZone -configuration Release -derivedDataPath ./build build
```

The app is produced at `build/Build/Products/Release/CutoutDropZone.app`.

## Permissions

CutoutDropZone doesn't request Accessibility, Screen Recording, Microphone, Camera, or any other system permission, and the source contains no usage-description strings for them. The only access is what you grant through standard macOS panels:

- **Files you choose or drop**: images you add via the open panel or drag and drop are read, and nothing else.
- **Output folder**: the folder you pick for **Export All** is where cutouts are written.
- **Caches folder**: temporary files for drag-out and for images dropped from browsers are kept in `~/Library/Caches/CutoutDropZone` and cleared on the next launch.

## Built with AI

CutoutDropZone was written by [Claude Code](https://claude.com/claude-code) inside an automated pipeline, from a plain-English spec. No code, binaries or assets from any commercial app were used; it is a clean-room reimplementation of a feature set, not a copy.

What that means in practice:

- The full source is in this repo under the MIT license. Read it before you run it.
- No network calls, no analytics, no third-party dependencies. Only Apple frameworks.
- Ad-hoc signed and not notarized, which is why Gatekeeper warns on first launch.
- It has had less human review than a hand-written app. Bug reports and pull requests are welcome.

## Support ❤️

If CutoutDropZone saves you time, you can support its development: [Support Or (Leo) Davidai ❤️](https://ko-fi.com/leodavidai). There is also a **Support / Donate ❤️** button in the app.

## License

MIT © Or Davidai Bachar
