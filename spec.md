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

### Clipboard / Drag / Keyboard round (2026-06-12, complete)

**Pasteboard formats** (`Assets/Shared/AssetPasteboardWriter.swift`, `@MainActor`):

| Copy target | Types written (writer-preference order) |
| --- | --- |
| Single vector | `.string` (SVG XML — Figma pastes editable vectors), `public.svg-image`, `.fileURL` (temp `.svg`), `.tiff` (raster last resort) |
| Single bitmap | `.png` (authoritative bytes), `.tiff`, `.fileURL` (temp `.png`) |
| Multiple assets | pure file URLs from one fresh temp dir, filenames deduped — no image flavor (image targets would silently drop N−1) |

The pasteboard is only cleared once a payload is known-good — a failed temp write never destroys the existing clipboard. Empty input is a no-op.

**Shipped this round:**

- `Assets/Shared/AssetTempFiles.swift` — unique per-operation temp export dirs under `AssetsExport/<UUID>/`, stale cleanup (>1h) on catalog load
- `Asset.transferRepresentation` rewritten — vectors drag/export as `.svg`, bitmaps as `.png` (file representation first, data fallback, `exportingCondition` per kind), each via a fresh temp dir
- `CatalogViewModel` owns `viewMode` (lifted from `AssetGridView`), `gridColumnCount`, `selectionAnchorID`, and `selectRange(to:)` (Finder-style range selection); `AssetGridView` uses `@Bindable` + `$viewModel.searchText`
- Grid: real column count measured via `onGeometryChange` (replaces the width estimate); `ScrollViewReader` keeps arrow-key selection on-screen; macOS 26 drag container carries the whole selection (single-tile drag on macOS 15 — documented limitation)
- List: rows-builder `Table` bound to `viewModel.selectedAssets` — native multi-select, shift/cmd-click, row drag via `TableRow.draggable`, selection-aware context menus shared with the grid
- `QuickLookModifier` monitor — scoped per window: handles keys from the host window while key, or from the Quick Look panel while the host is main (the panel becomes key when it opens, so arrow-flipping with QL open works in both modes); the host window is captured weakly (`WeakWindowBox` + `WindowReader`) so closing a document leaks nothing; passes through text editing and Cmd/Opt/Ctrl shortcuts; Esc clears search when QL is closed; Shift+arrows extend the range selection; `ensureResponder()` targets the main window and always re-asserts first responder
- Edit-menu architecture (`Assets/App/AssetCommands.swift`): `AssetDocumentActions` published per window via `.focusedSceneValue(\.assetActions)`; commands route only to the focused catalog and disable elsewhere. Copy/Select All check the text first responder so search-field editing wins; Cut/Paste always route to the text responder (the search-paste fix); Copy Name (Cmd+Opt+C), Export All/Selected (Cmd+Shift+E / Cmd+E), Find (Cmd+F) focuses search. NotificationCenter command routing removed, dead "Toggle Preview" item deleted
- Copy, Copy Name, and Export Selected share one target priority: multi-selection → previewed asset → single selection

**Risk outcomes (R1–R4):** R4 — macOS 26 drag-container API spellings (`draggable(containerItemID:)`, `dragContainer(for:)`, `dragContainerSelection(_:)`) compiled as planned. R1 (Figma file-promise drop), R2 (Table multi-row drag), R3 (`.searchable(isPresented:)` focusing the field) need manual runtime verification — not yet user-confirmed. Fallbacks if they fail: pre-written file at drag start (R1), `TableRow.itemProvider` (R2), walk the toolbar for the `NSSearchField` and make it first responder (R3).

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
