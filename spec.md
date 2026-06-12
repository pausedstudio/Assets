# Assets — Spec

_Last updated: 2026-06-12_

## Overview

macOS document-based app for browsing, previewing, and exporting assets from compiled `.car` (Asset Catalog) files. Also supports `.caar` / `.caml` / `.ca` Core Animation archives.

## Goals

- Browse and preview assets inside `.car` files
- Support Core Animation files (`.caar`, `.caml`, `.ca`)
- Quick Look integration
- Export assets

## Scope

**In scope:** Document-based macOS app, asset catalog browsing, Core Animation playback, Quick Look.
**Out of scope:** _TBD_

## Stack

- Swift + SwiftUI (document-based with DocumentGroup)
- CoreUI / CoreSVG / Quartz (private frameworks via Obj-C bridge)
- XcodeGen (`project.yml`)

## Architecture

- **Assets** (main app) — SwiftUI document-based app with two DocumentGroups:
  - `AssetCatalogDocument` (ReferenceFileDocument) for `.car` / `.app` / `.bundle` files
  - `CoreAnimationDocument` (FileDocument) for `.caar` / `.caml` / `.ca` files
- **AssetCatalogKit** (framework) — Obj-C bridge to CoreUI/CoreSVG private frameworks
- **AssetCatalogQuickLook** (QL extension) — Quick Look previewer for `.car` files

### Key Files

- `project.yml` — XcodeGen config (regenerate with `xcodegen generate`)
- `Assets/Assets-Bridging-Header.h` — Bridges AssetCatalogKit + QuartzCorePrivate.h
- `Assets/App/AssetsApp.swift` — Entry point with both DocumentGroups
- `Assets/Features/Catalog/` — Asset catalog browsing (models, viewmodels, views)
- `Assets/Features/CoreAnimation/` — Core Animation preview (models, views)

## Decisions

- XcodeGen for project generation
- Private framework access via Obj-C bridge
- Quick Look integration via `QuickLookCoordinator` + `QLPreviewPanel`

## Current State

### Clipboard / Drag / Keyboard round (2026-06-12, in progress)

- `Assets/Shared/AssetTempFiles.swift` — unique per-operation temp export dirs under `AssetsExport/<UUID>/`, stale cleanup (>1h) on catalog load
- `Assets/Shared/AssetPasteboardWriter.swift` — vector-aware copy: SVG text + `public.svg-image` + file URL with TIFF last (vectors); PNG-first (bitmaps); multi-asset copy writes deduped temp files as pure file URLs
- `Asset.transferRepresentation` rewritten — vectors drag/export as `.svg`, bitmaps as `.png`, each via a fresh temp dir
- `CatalogViewModel` now owns `viewMode` (lifted from `AssetGridView`), `gridColumnCount`, `selectionAnchorID`, and `selectRange(to:)` (Finder-style range selection); `AssetGridView` uses `@Bindable` + `$viewModel.searchText`
- `QuickLookModifier` monitor rewritten — scoped to its host window via `WindowReader` + key-window guard (multi-window safe); passes through text editing and Cmd/Opt/Ctrl shortcuts; Esc clears search when Quick Look is closed; list mode arrows move ±1 (native Table nav when the Table is focused); grid mode uses `viewModel.gridColumnCount`; Shift+arrows extend the range selection. `ensureResponder()` always re-asserts first responder so Quick Look opens after the Table had focus
- Remaining this round: grid geometry measurement + scroll-to-selection, Table multi-select/drag rewrite, grid drag container (macOS 26), FocusedValues command migration (Edit menu / paste fix)

## Open Questions

_TBD_

## Notes

### Recent Changes (2026-03-29) — Quick Look

- New `QuickLookCoordinator.swift` — manages `QLPreviewPanel` lifecycle, writes temp image files
- `QuickLookResponderView` (NSView) accepts panel control so the responder chain works
- `QuickLookResponder` (NSViewRepresentable) bridges into SwiftUI
- Spacebar toggles Quick Look on/off for the currently selected asset
- "Quick Look" added to asset context menu in grid and list views
- Added `Quartz.framework` SDK dependency in `project.yml`

### Previous Changes (2026-03-15) — Core Animation

- Added Core Animation file support (`.caar`, `.caml`, `.ca` bundle) — ported from Shasta
- `Assets/Private Headers/QuartzCorePrivate.h` — CAPackage, CAStateController private API declarations
- `Assets/Features/CoreAnimation/` — Document model, views (CAMLView, CAMLContainerView, CoreAnimationView)
- Updated bridging header, project.yml with document types and UTImportedTypeDeclarations
- Second `DocumentGroup` in AssetsApp.swift for Core Animation files
- Full playback controls: play/pause, scrub timeline, speed, state cycling
