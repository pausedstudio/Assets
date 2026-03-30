# Assets

macOS app for browsing, previewing, and exporting assets from compiled `.car` (Asset Catalog) files. Also supports Core Animation archives (`.caar`, `.caml`, `.ca`).

## Platform

macOS

## Features

- Open `.car` files directly or drag in an `.app` / `.bundle` to inspect its embedded asset catalog
- Grid and list views with sidebar navigation by asset type
- Asset preview panel with edit view
- **Quick Look** — spacebar toggles a QL panel for the selected asset; also available via context menu
- Core Animation file support — open `.caar` / `.caml` / `.ca` bundles with full playback controls (play/pause, scrub, speed, state cycling)
- Export assets

## Architecture

| Target                    | Description                                                                                                             |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Assets**                | SwiftUI document-based app. Two `DocumentGroup`s: one for `.car` / `.app` / `.bundle`, one for Core Animation archives. |
| **AssetCatalogKit**       | Obj-C framework that bridges CoreUI and CoreSVG private frameworks for reading `.car` files.                            |
| **AssetCatalogQuickLook** | Quick Look extension for previewing `.car` files in Finder.                                                             |

Key source layout inside `Assets/`:

- `App/AssetsApp.swift` — entry point, both DocumentGroups
- `Features/Catalog/` — asset catalog browsing (Models, ViewModels, Views)
- `Features/Catalog/Views/QuickLookCoordinator.swift` — QLPreviewPanel lifecycle, temp file management
- `Features/CoreAnimation/` — Core Animation preview (Models, Views)

## Built With

Swift, SwiftUI, AppKit, Quartz (QuickLook), XcodeGen (`project.yml`)

## Setup

```
xcodegen generate
```

Open `Assets.xcodeproj` and build.
