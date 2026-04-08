# Assets — Spec

_Last updated: 2026-04-07_

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

_TBD_

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
