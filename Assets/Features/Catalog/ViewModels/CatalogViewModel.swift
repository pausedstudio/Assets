//
//  CatalogViewModel.swift
//  Assets
//
//  ViewModel for managing asset catalog state
//

import SwiftUI
import Combine
import AssetCatalogKit

/// `@unchecked Sendable` is safe because background filter tasks only read an
/// immutable input snapshot (`AssetFilterEngine.Request`) plus the lock-guarded
/// `AssetFilterCaches`; every observable property is mutated on the main thread.
@Observable
final class CatalogViewModel: @unchecked Sendable {
    // MARK: - State

    var assets: [Asset] = [] {
        didSet { rebuildSidebarSummaries() }
    }
    var filteredAssets: [Asset] = []
    var selectedCategory: AssetCategory = .all
    var selectedGroup: AssetGroup? = nil
    var selectedAssets: Set<Asset.ID> = []
    var selectionAnchorID: Asset.ID?
    var viewMode: ViewMode = .grid
    var gridColumnCount: Int = 4
    var searchText: String = "" {
        didSet { scheduleFilter(debounce: .milliseconds(120)) }
    }

    // Sorting
    var sortOption: SortOption = .name {
        didSet { scheduleFilter() }
    }

    // Color filter
    var colorFilter: Color? = nil {
        didSet { scheduleFilter() }
    }
    var colorFilterTolerance: Double = 0.15

    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var error: String?
    var catalogName: String = ""

    // MARK: - View Mode

    enum ViewMode: String, CaseIterable {
        case grid, list

        var iconName: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    // MARK: - Sort Options

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case type = "Type"
        case hue = "Color"

        var iconName: String {
            switch self {
            case .name: return "textformat"
            case .size: return "ruler"
            case .type: return "square.grid.2x2"
            case .hue: return "paintpalette"
            }
        }
    }

    // MARK: - Sidebar Data

    // Stored rather than computed: SidebarView reads these on every render,
    // so they're rebuilt once per `assets` change instead of per body eval.
    private(set) var categories: [AssetCategory] = AssetCategory.defaultCategories
    private(set) var groups: [AssetGroup] = []

    // MARK: - Computed Properties

    var selectedAssetObjects: [Asset] {
        assets.filter { selectedAssets.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedAssets.isEmpty
    }

    // MARK: - Private

    private var reader: AssetCatalogReader?
    private var fileURL: URL?

    private let filterCaches = AssetFilterCaches()
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var filterGeneration = 0
    @ObservationIgnored private var awaitingFirstFilterResult = false

    // MARK: - Loading

    func loadCatalog(from url: URL) {
        AssetTempFiles.cleanUpStale()
        fileURL = url
        isLoading = true
        loadingProgress = 0
        error = nil
        assets = []
        filteredAssets = []
        selectedAssets = []

        // Drop any in-flight filter so a stale result can't land in the new catalog
        filterTask?.cancel()
        filterGeneration += 1
        filterCaches.reset()
        awaitingFirstFilterResult = false

        reader = AssetCatalogReader(fileURL: url)
        reader?.thumbnailSize = NSSize(width: 128, height: 128)

        reader?.read(completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                if let readerError = self.reader?.error {
                    self.error = readerError.localizedDescription
                    self.isLoading = false
                } else {
                    self.catalogName = self.reader?.catalogName ?? url.lastPathComponent
                    self.assets = (self.reader?.assets ?? []).map { Asset(from: $0) }
                    // isLoading stays true until this first filter result is
                    // applied, so the "No Assets" empty state never flashes
                    // between load completion and the filter landing.
                    self.awaitingFirstFilterResult = true
                    self.scheduleFilter()
                }

                self.loadingProgress = 1.0
            }
        }, progressHandler: { [weak self] progress in
            Task { @MainActor in
                self?.loadingProgress = progress
            }
        })
    }

    func cancelLoading() {
        reader?.cancelReading()
        isLoading = false
        awaitingFirstFilterResult = false
    }

    // MARK: - Filtering

    func selectCategory(_ category: AssetCategory) {
        selectedCategory = category
        selectedGroup = nil  // Deselect group when selecting category
        scheduleFilter()
    }

    func selectGroup(_ group: AssetGroup?) {
        selectedGroup = group
        if group != nil {
            selectedCategory = .all  // Reset category when selecting group
        }
        scheduleFilter()
    }

    func clearColorFilter() {
        colorFilter = nil
    }

    /// Debounces, snapshots every filter input, and runs the filter pipeline
    /// off the main thread so the search field renders keystrokes and pastes
    /// immediately. Latest-wins: each call cancels the previous task and bumps
    /// the generation so a stale result is never applied.
    private func scheduleFilter(debounce: Duration = .zero) {
        filterGeneration += 1
        let generation = filterGeneration

        let request = AssetFilterEngine.Request(
            assets: assets,
            searchText: searchText,
            groupName: selectedGroup?.name,
            categoryTypes: selectedCategory.assetTypes != AssetCategory.all.assetTypes
                ? selectedCategory.assetTypes : nil,
            sortOption: sortOption,
            colorTarget: colorFilter?.hsb,
            colorTolerance: colorFilterTolerance,
            cacheEpoch: filterCaches.currentEpoch
        )
        let caches = filterCaches

        filterTask?.cancel()
        filterTask = Task(priority: .userInitiated) {
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                if Task.isCancelled { return }
            }
            // nil result means the task was cancelled mid-compute
            guard let result = AssetFilterEngine.filteredAssets(for: request, caches: caches) else { return }
            await MainActor.run {
                guard generation == self.filterGeneration else { return }
                self.filteredAssets = result
                if self.awaitingFirstFilterResult {
                    self.awaitingFirstFilterResult = false
                    self.isLoading = false
                }
            }
        }
    }

    private func rebuildSidebarSummaries() {
        var cats = AssetCategory.defaultCategories
        for i in cats.indices {
            cats[i].count = assets.filter { cats[i].assetTypes.contains($0.assetType) }.count
        }
        categories = cats

        // Extract groups from asset names using CamelCase split
        var groupDict: [String: Int] = [:]
        for asset in assets {
            groupDict[AssetFilterEngine.extractGroupName(from: asset.name), default: 0] += 1
        }
        groups = groupDict.map { AssetGroup(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Selection

    func selectAll() {
        selectedAssets = Set(filteredAssets.map(\.id))
    }

    func deselectAll() {
        selectedAssets = []
    }

    func toggleSelection(_ asset: Asset) {
        if selectedAssets.contains(asset.id) {
            selectedAssets.remove(asset.id)
        } else {
            selectedAssets.insert(asset.id)
        }
    }

    /// Finder-style range selection: selects the contiguous run of `filteredAssets`
    /// from the anchor to the target. Repeated calls re-extend from the same anchor.
    func selectRange(to asset: Asset) {
        guard let targetIndex = filteredAssets.firstIndex(where: { $0.id == asset.id }) else { return }

        let anchorID = selectionAnchorID.flatMap { id in
            filteredAssets.contains { $0.id == id } ? id : nil
        } ?? selectedAssets.first { id in
            filteredAssets.contains { $0.id == id }
        }

        guard let anchorID,
              let anchorIndex = filteredAssets.firstIndex(where: { $0.id == anchorID }) else {
            selectedAssets = [asset.id]
            selectionAnchorID = asset.id
            return
        }

        selectionAnchorID = anchorID
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedAssets = Set(filteredAssets[range].map(\.id))
    }

    // MARK: - Export

    func exportAssets(_ assets: [Asset], to directory: URL) async {
        let dictionaries = assets.map { asset -> [String: Any] in
            return [
                "filename": asset.filename,
                "data": asset.data
            ]
        }

        let exporter = ImageExporter(images: dictionaries)
        await exporter.export(toDirectoryAt: directory)
    }

    @MainActor
    func copyAssetsToPasteboard(_ assets: [Asset]) {
        AssetPasteboardWriter.copy(assets)
    }

    @MainActor
    func copySelectedAssets() {
        copyAssetsToPasteboard(selectedAssetObjects)
    }

    @MainActor
    func copySelectedAssetNames() {
        AssetPasteboardWriter.copyNames(of: selectedAssetObjects)
    }

    // MARK: - Editing

    func replaceImage(for asset: Asset, with newImage: CGImage) async throws {
        guard let url = fileURL else {
            throw EditError.noFileURL
        }

        // Create editor - throws on error
        let editor = try AssetCatalogEditor(fileURL: url)

        do {
            try editor.replaceImageNamed(asset.name, scale: asset.scale, with: newImage)
            try editor.save()
            editor.close()

            // Reload the catalog to reflect changes
            loadCatalog(from: url)
        } catch {
            editor.close()
            throw error
        }
    }

    func replaceColor(for asset: Asset, with newColor: CGColor) async throws {
        guard let url = fileURL else {
            throw EditError.noFileURL
        }

        let editor = try AssetCatalogEditor(fileURL: url)

        do {
            try editor.replaceColorNamed(asset.name, with: newColor)
            try editor.save()
            editor.close()

            // Reload the catalog to reflect changes
            loadCatalog(from: url)
        } catch {
            editor.close()
            throw error
        }
    }

    func deleteAsset(_ asset: Asset) async throws {
        guard let url = fileURL else {
            throw EditError.noFileURL
        }

        let editor = try AssetCatalogEditor(fileURL: url)

        do {
            try editor.removeRenditionNamed(asset.name, scale: asset.scale)
            try editor.save()
            editor.close()

            // Reload the catalog to reflect changes
            loadCatalog(from: url)
        } catch {
            editor.close()
            throw error
        }
    }

    enum EditError: LocalizedError {
        case noFileURL
        case editorCreationFailed
        case replaceFailed
        case deleteFailed
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .noFileURL: return "No file URL available"
            case .editorCreationFailed: return "Failed to create editor"
            case .replaceFailed: return "Failed to replace asset"
            case .deleteFailed: return "Failed to delete asset"
            case .saveFailed: return "Failed to save changes"
            }
        }
    }
}
