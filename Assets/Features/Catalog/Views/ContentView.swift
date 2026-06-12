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
  @State private var isSearchPresented = false
  @State private var showingExportPanel = false
  @State private var exportMode: ExportMode = .all

  enum ExportMode {
    case all, selected
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(viewModel: document.viewModel)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    } detail: {
      AssetGridView(
        viewModel: document.viewModel,
        selectedAsset: $selectedAsset,
        isSearchPresented: $isSearchPresented
      )
    }
    .navigationTitle(
      document.viewModel.catalogName.isEmpty ? "Assets" : document.viewModel.catalogName
    )
    .onAppear {
      document.viewModel.loadCatalog(from: document.fileURL)
    }
    .focusedSceneValue(
      \.assetActions,
      AssetDocumentActions(
        hasSelection: document.viewModel.hasSelection || selectedAsset != nil,
        copy: copyAssets,
        copyName: copyAssetNames,
        selectAll: { document.viewModel.selectAll() },
        exportAll: {
          exportMode = .all
          showingExportPanel = true
        },
        exportSelected: {
          exportMode = .selected
          showingExportPanel = true
        },
        focusSearch: { isSearchPresented = true }
      )
    )
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
    let vm = document.viewModel
    if vm.selectedAssets.count > 1 {
      vm.copySelectedAssets()
    } else if let asset = selectedAsset {
      vm.copyAssetsToPasteboard([asset])
    } else if vm.hasSelection {
      vm.copySelectedAssets()
    }
  }

  private func copyAssetNames() {
    let vm = document.viewModel
    if vm.selectedAssets.count > 1 {
      vm.copySelectedAssetNames()
    } else if let asset = selectedAsset {
      AssetPasteboardWriter.copyNames(of: [asset])
    } else if vm.hasSelection {
      vm.copySelectedAssetNames()
    }
  }

  private func handleExport(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }

    Task {
      let vm = document.viewModel
      let assets: [Asset]
      switch exportMode {
      case .all:
        assets = vm.filteredAssets
      case .selected:
        // Mirror the copy commands: fall back to the previewed asset when
        // the multi-selection set is empty, so Export Selected never writes
        // an empty folder.
        if !vm.selectedAssetObjects.isEmpty {
          assets = vm.selectedAssetObjects
        } else if let asset = selectedAsset {
          assets = [asset]
        } else {
          assets = []
        }
      }

      await vm.exportAssets(assets, to: url)
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
