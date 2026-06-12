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

Fully functional browser for `.car` catalogs and Core Animation archives. Grid and list view modes with search (Cmd+F focuses, Esc clears), sidebar filtering, sorting, Quick Look (spacebar toggle + arrow flipping in both modes), and export (all / selected). Clipboard and drag-out are format-correct per asset kind: vectors copy and drag as SVG, bitmaps as PNG. Multi-select works in both modes (native in list; click/Cmd/Shift in grid); list rows drag the full selection; grid multi-drag uses the macOS 26 drag container. Edit-menu commands route per focused window via FocusedValues, so multi-window documents no longer cross-fire. Smoke-tested 2026-06-12 against a system catalog (launches, loads, renders grid).

**Known limitations:**

- Arrow-key fallback when the list Table isn't first responder has no auto-scroll (SwiftUI `Table` exposes no scroll API; heals on next click — focused Table scrolls natively)
- On macOS 15 a grid drag carries only the grabbed tile (multi-drag there is the list-mode path; the drag-container API is macOS 26+)
- Figma drag-and-drop of vectors (file-promise drop) pending manual verification; Figma paste (SVG text) and export are the verified paths

## Open Questions

- Does Figma accept the `FileRepresentation` file-promise drop for vectors? (Fallback if not: pre-write the file at drag start)
- Does `.searchable(isPresented:)` reliably move focus to the field on macOS 15? (Fallback: walk the toolbar for the `NSSearchField`)

## Notes

### Recent Changes (2026-06-12) — Load/Filter Race Hardening

- `loadCatalog` is `@MainActor` (edit methods `await` it), cancels the previous `AssetCatalogReader`, and its completion/progress closures capture their owning reader and bail on an identity mismatch — a stale completion can no longer read the new reader's mid-load state (NSMutableArray copy-during-mutation) or mark a partial load complete, and `filterTask`/`filterGeneration` are only ever touched on main.
- Filter caches reset in `assets.didSet`, not just at load start: the sorted-base cache is keyed by (sort option, epoch), so a filter scheduled while `assets` was empty mid-load could otherwise poison the cache for the loaded catalog (permanent "No Assets" on a full catalog).
- `Asset.dominantColorHSB` samples a bitmap decoded from the immutable `data` bytes (PNG directly; SVG rasterized via a locally created NSImage) instead of `thumbnail.tiffRepresentation` — background color sampling no longer exercises an NSImage instance shared with main-thread rendering.
- Grid empty state branches on `appliedSearchText` (the query that produced the current `filteredAssets`) instead of the live `searchText`, so clearing a zero-result search no longer flashes "No Assets" during the debounce window.

### Recent Changes (2026-06-12) — Search/Filter Performance

- **Async filter pipeline** (`CatalogViewModel.scheduleFilter`): `searchText` no longer filters synchronously in `didSet` — typing/pasting renders instantly. Search changes debounce 120 ms; sort/category/group/color changes run immediately. Each call snapshots all inputs into `AssetFilterEngine.Request` on the main thread, cancels the prior task, bumps a generation counter (latest-wins), and computes on a background `Task(priority: .userInitiated)`; results apply on `MainActor` only if the generation still matches. `isLoading` stays true until the first filter result lands so the empty state never flashes.
- **`AssetFilterEngine`** (`Assets/Features/Catalog/ViewModels/AssetFilterEngine.swift`): stateless port of the old `filterAssets()` — identical semantics (group > category precedence, regex/metadata/fuzzy smart search, fuzzy relevance ranking still discarded by the sort order). All per-asset passes check `Task.isCancelled` periodically. An `OSSignposter` interval (subsystem `com.paused.Assets`, category `perf`, name `filterAssets`) records duration + in/out counts.
- **Caches** (`AssetFilterCaches`, single-`NSLock`-guarded, epoch-invalidated on catalog load): presorted base per `SortOption` (the ~20–30 ms ICU name sort now runs once per catalog+option, not per keystroke — filters preserve base order); memoized `dominantColorHSB` per `Asset.ID` (was recomputed via TIFF encode + pixel sampling on every call despite a comment claiming caching; hue sort comparators no longer compute pixels — decorate-sort-undecorate). `Asset.searchKey` (lowercased name) precomputed at init. `categories`/`groups` are stored properties rebuilt on `assets` change instead of computed per sidebar render.
- `CatalogViewModel` remains `@unchecked Sendable`: background tasks only read the immutable request snapshot + lock-guarded caches; observable mutations stay on the main thread.
- **Polish round (2026-06-12):** load completion now maps the ~6k reader dictionaries → `Asset` (each init lowercases a search key) in a detached background task before assigning `assets` on main, guarded by reader identity so a reload mid-map can't apply stale results — removes the one-time main-thread hitch at load completion. `CheckerboardView` tiles one cached rasterized 2×2-square `NSImage` via `ImagePaint` (cache keyed by `squareSize`; grid uses 8, preview 12) instead of filling ~200 individual `Path` rects in a per-cell `Canvas` on every cell materialization during scroll.
- Summary of the architecture: search input → 120 ms debounce → immutable snapshot (`AssetFilterEngine.Request`) → background compute with periodic cancellation checks → generation-guarded (latest-wins) `filteredAssets` assignment on main. Caches: per-asset `searchKey` (init-time), per-sort-option presorted base + per-asset HSB memo (`AssetFilterCaches`, epoch-invalidated per catalog), stored `categories`/`groups` rebuilt on `assets` change.

### Recent Changes (2026-06-12) — Clipboard / Drag / Keyboard

- **Edit-menu / FocusedValues command architecture** (`Assets/App/AssetCommands.swift`): `AssetDocumentActions` published per window via `.focusedSceneValue(\.assetActions)`; menu items act only on the focused catalog and disable elsewhere (Settings, Core Animation windows). Copy/Select All check the text first responder so search-field editing wins; Cut/Paste always route to the text responder (the search-paste fix); Copy Name (Cmd+Opt+C), Export All/Selected (Cmd+Shift+E / Cmd+E), Find (Cmd+F) focuses search. NotificationCenter command routing removed; dead "Toggle Preview" item deleted. Copy, Copy Name, and Export Selected share one target priority: multi-selection → previewed asset → single selection.
- **Pasteboard formats** (`Assets/Shared/AssetPasteboardWriter.swift`, `@MainActor`) — type order is writer preference:

  | Copy target | Types written (in order) |
  | --- | --- |
  | Single vector | `.string` (SVG XML — Figma pastes editable vectors), `public.svg-image`, `.fileURL` (temp `.svg`), `.tiff` (raster last resort) |
  | Single bitmap | `.png` (authoritative bytes), `.tiff`, `.fileURL` (temp `.png`) |
  | Multiple assets | pure file URLs from one fresh temp dir, filenames deduped — no image flavor (image targets would silently drop N−1) |

  The pasteboard is cleared only once a payload is known-good — a failed temp write never destroys the existing clipboard; empty input is a no-op.
- **Transferable** (`Asset.transferRepresentation`): vectors export as `.svg`, bitmaps as `.png`, gated by `exportingCondition`; `FileRepresentation` declared before `DataRepresentation` so file-oriented receivers take the file and data receivers fall through; every export writes into a fresh `AssetsExport/<UUID>/` temp dir (`Assets/Shared/AssetTempFiles.swift`, stale dirs >1h cleaned on catalog load), so receivers get the real filename and never stale bytes.
- **Monitor / window scoping** (`QuickLookModifier`): the key-event monitor is scoped to its host window (captured weakly via `WindowReader` + `WeakWindowBox`) — it handles keys only while its window is key, or from the Quick Look panel while the host is main, so a second document window never steals keys. Passes through text editing and Cmd/Opt/Ctrl shortcuts; Esc clears search when QL is closed; Shift+arrows extend the range selection; list mode moves ±1 row, grid mode uses the measured `gridColumnCount` (via `onGeometryChange`, replacing the width estimate); `ScrollViewReader` keeps grid selection on-screen; `ensureResponder()` always re-asserts first responder so spacebar QL works after clicking a Table row.
- **Table multi-select + drag**: list rewritten as a rows-builder `Table` bound to `viewModel.selectedAssets` — native multi-select (Cmd/Shift-click, shift+arrows), row drag via `TableRow.draggable` carries the whole selection, selection-aware context menus shared with the grid. `CatalogViewModel` owns `viewMode`, `gridColumnCount`, `selectionAnchorID`, and `selectRange(to:)` (Finder-style ranges).
- **Grid drag container (macOS 26)**: tiles use `draggable(containerItemID:)` inside a `dragContainer(for: Asset.self)` with `dragContainerSelection`, so dragging a selected tile carries the entire selection; the macOS 15 baseline keeps the single-item `.draggable(asset)` path.
- **Known limitations**: unfocused-Table arrow fallback has no auto-scroll; macOS 15 grid drag is single-item; Figma vector drop (file promise) pending manual test — paste path verified by design (SVG text first).

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
