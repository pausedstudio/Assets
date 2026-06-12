//
//  AssetGridView.swift
//  Assets
//
//  Grid and list display of asset thumbnails
//

import Quartz
import SwiftUI

struct AssetGridView: View {
  @Bindable var viewModel: CatalogViewModel
  @Binding var selectedAsset: Asset?
  @Binding var isSearchPresented: Bool

  private static let itemMinWidth: CGFloat = 120
  private static let itemSpacing: CGFloat = 12

  private let gridColumns = [GridItem(.adaptive(minimum: itemMinWidth, maximum: 180), spacing: itemSpacing)]

  var body: some View {
    Group {
      if viewModel.isLoading {
        loadingView
      } else if let error = viewModel.error {
        errorView(error)
      } else if viewModel.filteredAssets.isEmpty {
        emptyView
      } else {
        if viewModel.viewMode == .grid {
          gridContent
        } else {
          listContent
        }
      }
    }
    .onChange(of: viewModel.selectedAssets) { oldValue, newValue in
      let added = newValue.subtracting(oldValue)
      if newValue.isEmpty {
        selectedAsset = nil
      } else if added.count == 1, let addedID = added.first {
        selectedAsset = viewModel.filteredAssets.first { $0.id == addedID }
      } else if let current = selectedAsset, !newValue.contains(current.id) {
        selectedAsset = viewModel.filteredAssets.first { newValue.contains($0.id) }
      }
    }
    .searchable(
      text: $viewModel.searchText,
      isPresented: $isSearchPresented,
      placement: .toolbar,
      prompt: "Search"
    )
    .quickLook(asset: $selectedAsset, viewModel: viewModel)
    .toolbar {
      // View mode + Sort
      ToolbarItemGroup(placement: .secondaryAction) {
        Picker("View Mode", selection: $viewModel.viewMode) {
          ForEach(CatalogViewModel.ViewMode.allCases, id: \.self) { mode in
            Image(systemName: mode.iconName)
              .tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .help("Switch between grid and list view")

        sortMenu
      }

    }
  }

  // MARK: - Sort Menu

  @ViewBuilder
  private var sortMenu: some View {
    Menu {
      ForEach(CatalogViewModel.SortOption.allCases, id: \.self) { option in
        Button {
          viewModel.sortOption = option
        } label: {
          HStack {
            Image(systemName: option.iconName)
            Text(option.rawValue)
            if viewModel.sortOption == option {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down")
    }
    .help("Sort options")
  }

  // MARK: - Grid Content

  @ViewBuilder
  private var gridContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(columns: gridColumns, spacing: 12) {
          ForEach(viewModel.filteredAssets) { asset in
            AssetGridItem(
              asset: asset,
              size: Self.itemMinWidth,
              isSelected: viewModel.selectedAssets.contains(asset.id)
            )
            .background {
              GeometryReader { geo in
                Color.clear
                  .onChange(of: selectedAsset?.id) { _, newID in
                    if newID == asset.id {
                      updateSourceFrame(geo: geo, image: asset.thumbnail)
                    }
                  }
                  .onAppear {
                    if selectedAsset?.id == asset.id {
                      updateSourceFrame(geo: geo, image: asset.thumbnail)
                    }
                  }
              }
            }
            .onTapGesture {
              handleTap(asset)
            }
            .contextMenu {
              assetContextMenu(for: asset)
            }
            .modifier(AssetItemDrag(asset: asset))
          }
        }
        .modifier(AssetGridDragContainer(viewModel: viewModel))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
          viewModel.gridColumnCount = max(1, Int((width + Self.itemSpacing) / (Self.itemMinWidth + Self.itemSpacing)))
        }
        .padding()
      }
      .onChange(of: selectedAsset?.id) { _, newID in
        guard let newID else { return }
        proxy.scrollTo(newID, anchor: nil)
      }
    }
  }

  // MARK: - List Content

  @ViewBuilder
  private var listContent: some View {
    Table(of: Asset.self, selection: $viewModel.selectedAssets) {
      TableColumn("Name") { asset in
        HStack(spacing: 8) {
          Image(nsImage: asset.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
          Text(asset.name)
            .lineLimit(1)
        }
      }
      .width(min: 150, ideal: 250)

      TableColumn("Size") { asset in
        Text(asset.sizeString)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .width(80)

      TableColumn("Type") { asset in
        HStack(spacing: 4) {
          Image(systemName: asset.assetType.iconName)
            .foregroundStyle(.secondary)
          Text(asset.assetType.displayName)
        }
      }
      .width(80)
    } rows: {
      ForEach(viewModel.filteredAssets) { asset in
        TableRow(asset)
          .draggable(asset)
      }
    }
    .contextMenu(forSelectionType: Asset.ID.self) { ids in
      assetContextMenu(forIDs: ids)
    } primaryAction: { ids in
      if let id = ids.first {
        selectedAsset = viewModel.filteredAssets.first { $0.id == id }
      }
    }
  }

  @ViewBuilder
  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView(value: viewModel.loadingProgress)
        .progressViewStyle(.linear)
        .frame(width: 200)

      Text("Loading assets...")
        .foregroundStyle(.secondary)

      Text("\(Int(viewModel.loadingProgress * 100))%")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private func errorView(_ error: String) -> some View {
    ContentUnavailableView {
      Label("Error", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error)
    } actions: {
      Button("Try Again") {
        // Reload would go here
      }
    }
  }

  @ViewBuilder
  private var emptyView: some View {
    // Branch on the query that produced `filteredAssets`, not the live
    // searchText — the live text updates instantly while results lag by the
    // debounce window, which would flash "No Assets" when clearing a
    // zero-result search in a populated catalog.
    if viewModel.appliedSearchText.isEmpty {
      ContentUnavailableView(
        "No Assets",
        systemImage: "photo.on.rectangle.angled",
        description: Text("This catalog doesn't contain any viewable assets.")
      )
    } else {
      ContentUnavailableView.search(text: viewModel.appliedSearchText)
    }
  }

  // MARK: - Context Menu

  private var selectedAssetsInDisplayOrder: [Asset] {
    viewModel.filteredAssets.filter { viewModel.selectedAssets.contains($0.id) }
  }

  @ViewBuilder
  private func assetContextMenu(for asset: Asset) -> some View {
    let isInMultiSelection = viewModel.selectedAssets.count > 1 && viewModel.selectedAssets.contains(asset.id)
    assetContextMenu(targets: isInMultiSelection ? selectedAssetsInDisplayOrder : [asset])
  }

  @ViewBuilder
  private func assetContextMenu(forIDs ids: Set<Asset.ID>) -> some View {
    assetContextMenu(targets: viewModel.filteredAssets.filter { ids.contains($0.id) })
  }

  @ViewBuilder
  private func assetContextMenu(targets: [Asset]) -> some View {
    if targets.count > 1 {
      Button("Copy \(targets.count) Assets") {
        viewModel.copyAssetsToPasteboard(targets)
      }

      Button("Copy Names") {
        AssetPasteboardWriter.copyNames(of: targets)
      }
    } else if let asset = targets.first {
      Button("Copy") {
        viewModel.copyAssetsToPasteboard([asset])
      }

      Button("Copy Name") {
        AssetPasteboardWriter.copyNames(of: [asset])
      }
    }

    if let asset = targets.first {
      Button("Quick Look") {
        QuickLookCoordinator.shared.preview(asset: asset)
      }

      Button("Show in Preview") {
        selectedAsset = asset
      }

      Divider()

      Button("Select") {
        viewModel.selectedAssets.formUnion(targets.map(\.id))
      }
    }
  }

  private func updateSourceFrame(geo: GeometryProxy, image: NSImage) {
    guard let window = NSApp.keyWindow else { return }
    let swiftUIFrame = geo.frame(in: .global)
    // SwiftUI .global is top-left origin relative to window content.
    // NSWindow expects bottom-left origin, so flip Y.
    let windowHeight = window.contentView?.bounds.height ?? window.frame.height
    let flippedRect = NSRect(
      x: swiftUIFrame.origin.x,
      y: windowHeight - swiftUIFrame.origin.y - swiftUIFrame.height,
      width: swiftUIFrame.width,
      height: swiftUIFrame.height
    )
    let screenFrame = window.convertToScreen(flippedRect)
    QuickLookCoordinator.shared.setSourceFrame(screenFrame, image: image)
  }

  private func handleTap(_ asset: Asset) {
    if NSEvent.modifierFlags.contains(.shift) {
      // Shift-click: Finder-style range selection from the anchor
      viewModel.selectRange(to: asset)
    } else if NSEvent.modifierFlags.contains(.command) {
      // Command-click: toggle selection; a newly selected item becomes the anchor
      viewModel.toggleSelection(asset)
      if viewModel.selectedAssets.contains(asset.id) {
        viewModel.selectionAnchorID = asset.id
      }
    } else {
      // Regular click: single selection, anchor, and show in preview
      viewModel.selectedAssets = [asset.id]
      viewModel.selectionAnchorID = asset.id
      selectedAsset = asset
    }
  }
}

// MARK: - Drag Modifiers

/// Per-item drag: on macOS 26 the item participates in the grid's drag container
/// (multi-item drags); earlier systems fall back to single-item draggable.
private struct AssetItemDrag: ViewModifier {
  let asset: Asset

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.draggable(containerItemID: asset.id)
    } else {
      content.draggable(asset) {
        AssetDragPreview(asset: asset)
      }
    }
  }
}

/// Grid-level drag container: on macOS 26, dragging a selected tile carries the
/// whole selection; earlier systems pass through unchanged.
private struct AssetGridDragContainer: ViewModifier {
  let viewModel: CatalogViewModel

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .dragContainer(for: Asset.self) { ids in
          viewModel.filteredAssets.filter { ids.contains($0.id) }
        }
        .dragContainerSelection(Array(viewModel.selectedAssets))
    } else {
      content
    }
  }
}

// MARK: - Grid Item

struct AssetGridItem: View {
  let asset: Asset
  let size: CGFloat
  let isSelected: Bool

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        CheckerboardView()
          .frame(width: size - 16, height: size - 16)
          .clipShape(RoundedRectangle(cornerRadius: 6))

        Image(nsImage: asset.thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: size - 20, height: size - 20)
      }

      Text(asset.name)
        .font(.caption2)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
    .padding(8)
    .frame(width: size, height: size + 28)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
    }
    .contentShape(Rectangle())
  }
}

// MARK: - Drag Preview

struct AssetDragPreview: View {
  let asset: Asset

  var body: some View {
    Image(nsImage: asset.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 80, height: 80)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .shadow(radius: 4)
  }
}

// MARK: - Checkerboard Background

struct CheckerboardView: View {
  var squareSize: CGFloat = 8

  var body: some View {
    Rectangle()
      .fill(ImagePaint(image: Image(nsImage: Self.tile(squareSize: squareSize))))
  }

  // One rasterized 2x2-square tile per square size, shared by every cell —
  // replaces a per-cell Canvas that filled ~200 individual Path rects on
  // each materialization during scroll.
  @MainActor private static var tileCache: [CGFloat: NSImage] = [:]

  @MainActor private static func tile(squareSize: CGFloat) -> NSImage {
    if let cached = tileCache[squareSize] { return cached }

    let side = squareSize * 2
    let tile = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
      NSColor(white: 0.95, alpha: 1).setFill()
      NSRect(x: 0, y: 0, width: side, height: side).fill()
      NSColor(white: 0.85, alpha: 1).setFill()
      NSRect(x: 0, y: 0, width: squareSize, height: squareSize).fill()
      NSRect(x: squareSize, y: squareSize, width: squareSize, height: squareSize).fill()
      return true
    }
    tileCache[squareSize] = tile
    return tile
  }
}
