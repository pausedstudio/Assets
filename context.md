# Assets - Context

## What This Is

macOS document-based app for browsing, previewing, and exporting assets from compiled `.car` (Asset Catalog) files. Also supports `.caar` / `.ca` Core Animation archives.

## Architecture

- **Assets** (main app) - SwiftUI document-based app with two DocumentGroups:
  - `AssetCatalogDocument` (ReferenceFileDocument) for `.car` / `.app` / `.bundle` files
  - `CoreAnimationDocument` (FileDocument) for `.caar` / `.caml` / `.ca` files
- **AssetCatalogKit** (framework) - Obj-C bridge to CoreUI/CoreSVG private frameworks
- **AssetCatalogQuickLook** (QL extension) - Quick Look previewer for `.car` files
- Uses XcodeGen (`project.yml`) to generate `.xcodeproj`

## Recent Changes (2026-03-15)

- Added Core Animation file support (`.caar`, `.caml`, `.ca` bundle) - ported from Shasta
  - `Assets/Private Headers/QuartzCorePrivate.h` - CAPackage, CAStateController private API declarations
  - `Assets/Features/CoreAnimation/` - Document model, views (CAMLView, CAMLContainerView, CoreAnimationView)
  - Updated bridging header, project.yml with document types and UTImportedTypeDeclarations
  - Second `DocumentGroup` in AssetsApp.swift for Core Animation files
  - Full playback controls: play/pause, scrub timeline, speed, state cycling

## Key Files

- `project.yml` - XcodeGen config (regenerate with `xcodegen generate`)
- `Assets/Assets-Bridging-Header.h` - Bridges AssetCatalogKit + QuartzCorePrivate.h
- `Assets/App/AssetsApp.swift` - Entry point with both DocumentGroups
- `Assets/Features/Catalog/` - Asset catalog browsing (models, viewmodels, views)
- `Assets/Features/CoreAnimation/` - Core Animation preview (models, views)
