//
//  ContentView.swift
//  Assets
//
//  Main content view with NavigationSplitView
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let document: AssetCatalogDocument

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedAsset: Asset?
    @State private var showingExportPanel = false
    @State private var exportMode: ExportMode = .all
    @State private var showPreview = true

    enum ExportMode {
        case all, selected
    }

    var body: some View {
        Group {
            if showPreview {
                // Three column layout with preview
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(viewModel: document.viewModel)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
                } content: {
                    AssetGridView(
                        viewModel: document.viewModel,
                        selectedAsset: $selectedAsset,
                        showPreview: $showPreview
                    )
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                } detail: {
                    if let asset = selectedAsset {
                        AssetPreviewView(asset: asset, viewModel: document.viewModel)
                    } else {
                        ContentUnavailableView(
                            "No Selection",
                            systemImage: "photo.on.rectangle",
                            description: Text("Select an asset to preview")
                        )
                    }
                }
            } else {
                // Two column layout without preview
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(viewModel: document.viewModel)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
                } detail: {
                    AssetGridView(
                        viewModel: document.viewModel,
                        selectedAsset: $selectedAsset,
                        showPreview: $showPreview
                    )
                }
            }
        }
        .navigationTitle(document.viewModel.catalogName.isEmpty ? "Assets" : document.viewModel.catalogName)
        .onAppear {
            document.viewModel.loadCatalog(from: document.fileURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAllAssets)) { _ in
            exportMode = .all
            showingExportPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSelectedAssets)) { _ in
            exportMode = .selected
            showingExportPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            document.viewModel.selectAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyAssets)) { _ in
            copyAssets()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
            showPreview.toggle()
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: ExportFolderDocument(),
            contentType: .folder,
            defaultFilename: "Exported Assets"
        ) { result in
            handleExport(result)
        }
    }

    private func copyAssets() {
        if let asset = selectedAsset {
            // Copy the previewed asset
            document.viewModel.copyAssetsToPasteboard([asset])
        } else {
            // Fall back to selected assets
            document.viewModel.copySelectedAssets()
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        Task {
            let assets = exportMode == .all ?
                document.viewModel.filteredAssets :
                document.viewModel.selectedAssetObjects

            await document.viewModel.exportAssets(assets, to: url)
        }
    }
}

// MARK: - Export Folder Document

struct ExportFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    init() {}
    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [:])
    }
}
