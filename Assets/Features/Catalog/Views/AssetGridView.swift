//
//  AssetGridView.swift
//  Assets
//
//  Grid and list display of asset thumbnails
//

import SwiftUI

struct AssetGridView: View {
    let viewModel: CatalogViewModel
    @Binding var selectedAsset: Asset?
    @Binding var showPreview: Bool
    @State private var viewMode: ViewMode = .grid
    @State private var isSearchPresented = false

    enum ViewMode: String, CaseIterable {
        case grid, list

        var iconName: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)]

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.filteredAssets.isEmpty {
                emptyView
            } else {
                if viewMode == .grid {
                    gridContent
                } else {
                    listContent
                }
            }
        }
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "Search"
        )
        .toolbar {
            // View mode + Sort
            ToolbarItemGroup(placement: .secondaryAction) {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch between grid and list view")

                sortMenu
            }

            // Preview toggle - far right
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPreview.toggle()
                } label: {
                    Image(systemName: "chevron.right.2")
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")
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
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.filteredAssets) { asset in
                    AssetGridItem(
                        asset: asset,
                        size: 120,
                        isSelected: viewModel.selectedAssets.contains(asset.id)
                    )
                    .onTapGesture {
                        handleTap(asset)
                    }
                    .contextMenu {
                        assetContextMenu(for: asset)
                    }
                    .draggable(asset) {
                        AssetDragPreview(asset: asset)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        Table(viewModel.filteredAssets, selection: Binding(
            get: { selectedAsset?.id },
            set: { id in
                if let id = id {
                    selectedAsset = viewModel.filteredAssets.first { $0.id == id }
                    if let asset = selectedAsset {
                        viewModel.selectedAssets = [asset.id]
                    }
                }
            }
        )) {
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
        }
        .contextMenu(forSelectionType: Asset.ID.self) { ids in
            if let id = ids.first, let asset = viewModel.filteredAssets.first(where: { $0.id == id }) {
                assetContextMenu(for: asset)
            }
        } primaryAction: { ids in
            if let id = ids.first, let asset = viewModel.filteredAssets.first(where: { $0.id == id }) {
                selectedAsset = asset
                viewModel.selectedAssets = [asset.id]
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
        if viewModel.searchText.isEmpty {
            ContentUnavailableView(
                "No Assets",
                systemImage: "photo.on.rectangle.angled",
                description: Text("This catalog doesn't contain any viewable assets.")
            )
        } else {
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    @ViewBuilder
    private func assetContextMenu(for asset: Asset) -> some View {
        Button("Copy") {
            viewModel.copyAssetsToPasteboard([asset])
        }

        Button("Show in Preview") {
            selectedAsset = asset
        }

        Divider()

        Button("Select") {
            viewModel.selectedAssets.insert(asset.id)
        }
    }

    private func handleTap(_ asset: Asset) {
        if NSEvent.modifierFlags.contains(.command) {
            // Command-click: toggle selection
            viewModel.toggleSelection(asset)
        } else if NSEvent.modifierFlags.contains(.shift) {
            // Shift-click: add to selection
            viewModel.selectedAssets.insert(asset.id)
        } else {
            // Regular click: single selection and show in preview
            viewModel.selectedAssets = [asset.id]
            selectedAsset = asset
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
        Canvas { context, size in
            let lightColor = Color(white: 0.95)
            let darkColor = Color(white: 0.85)

            for row in 0..<Int(size.height / squareSize) + 1 {
                for col in 0..<Int(size.width / squareSize) + 1 {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isEven ? lightColor : darkColor)
                    )
                }
            }
        }
    }
}


