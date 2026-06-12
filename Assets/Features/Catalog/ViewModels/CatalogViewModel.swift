//
//  CatalogViewModel.swift
//  Assets
//
//  ViewModel for managing asset catalog state
//

import SwiftUI
import Combine
import AssetCatalogKit

@Observable
final class CatalogViewModel: @unchecked Sendable {
    // MARK: - State

    var assets: [Asset] = []
    var filteredAssets: [Asset] = []
    var selectedCategory: AssetCategory = .all
    var selectedGroup: AssetGroup? = nil
    var selectedAssets: Set<Asset.ID> = []
    var searchText: String = "" {
        didSet { filterAssets() }
    }

    // Sorting
    var sortOption: SortOption = .name {
        didSet { filterAssets() }
    }

    // Color filter
    var colorFilter: Color? = nil {
        didSet { filterAssets() }
    }
    var colorFilterTolerance: Double = 0.15

    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var error: String?
    var catalogName: String = ""

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

    // MARK: - Computed Properties

    var categories: [AssetCategory] {
        var cats = AssetCategory.defaultCategories
        for i in cats.indices {
            cats[i].count = assets.filter { cats[i].assetTypes.contains($0.assetType) }.count
        }
        return cats
    }

    var groups: [AssetGroup] {
        // Extract groups from asset names using CamelCase split
        var groupDict: [String: Int] = [:]

        for asset in assets {
            let groupName = extractGroupName(from: asset.name)
            groupDict[groupName, default: 0] += 1
        }

        return groupDict.map { AssetGroup(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedAssetObjects: [Asset] {
        assets.filter { selectedAssets.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedAssets.isEmpty
    }

    // MARK: - Private

    private var reader: AssetCatalogReader?
    private var fileURL: URL?

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

        reader = AssetCatalogReader(fileURL: url)
        reader?.thumbnailSize = NSSize(width: 128, height: 128)

        reader?.read(completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                if let readerError = self.reader?.error {
                    self.error = readerError.localizedDescription
                } else {
                    self.catalogName = self.reader?.catalogName ?? url.lastPathComponent
                    self.assets = (self.reader?.assets ?? []).map { Asset(from: $0) }
                    self.filterAssets()
                }

                self.isLoading = false
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
    }

    // MARK: - Filtering

    func selectCategory(_ category: AssetCategory) {
        selectedCategory = category
        selectedGroup = nil  // Deselect group when selecting category
        filterAssets()
    }

    func selectGroup(_ group: AssetGroup?) {
        selectedGroup = group
        if group != nil {
            selectedCategory = .all  // Reset category when selecting group
        }
        filterAssets()
    }

    func clearColorFilter() {
        colorFilter = nil
    }

    private func filterAssets() {
        var result = assets

        // Filter by group (takes precedence)
        if let group = selectedGroup {
            result = result.filter { extractGroupName(from: $0.name) == group.name }
        }
        // Filter by category
        else if selectedCategory.assetTypes != AssetCategory.all.assetTypes {
            result = result.filter { selectedCategory.assetTypes.contains($0.assetType) }
        }

        // Filter by search (smart search)
        if !searchText.isEmpty {
            result = smartSearch(assets: result, query: searchText)
        }

        // Filter by color
        if let filterColor = colorFilter {
            result = filterByColor(assets: result, targetColor: filterColor)
        }

        // Apply sorting
        result = sortAssets(result)

        filteredAssets = result
    }

    // MARK: - Smart Search

    private func smartSearch(assets: [Asset], query: String) -> [Asset] {
        // Check if it's a regex pattern (contains special chars)
        let regexChars = CharacterSet(charactersIn: ".*+?[](){}|^$\\")
        let isRegex = query.unicodeScalars.contains { regexChars.contains($0) }

        if isRegex {
            return regexSearch(assets: assets, pattern: query)
        }

        // Check for metadata search (e.g., "size:100", "type:icon", "scale:2x")
        if query.contains(":") {
            return metadataSearch(assets: assets, query: query)
        }

        // Fuzzy search
        return fuzzySearch(assets: assets, query: query)
    }

    private func regexSearch(assets: [Asset], pattern: String) -> [Asset] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            // Fall back to fuzzy search if regex is invalid
            return fuzzySearch(assets: assets, query: pattern)
        }

        return assets.filter { asset in
            let range = NSRange(asset.name.startIndex..., in: asset.name)
            return regex.firstMatch(in: asset.name, options: [], range: range) != nil
        }
    }

    private func metadataSearch(assets: [Asset], query: String) -> [Asset] {
        let parts = query.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return fuzzySearch(assets: assets, query: query)
        }

        let field = String(parts[0]).lowercased()
        let value = String(parts[1]).lowercased()

        return assets.filter { asset in
            switch field {
            case "size", "width", "w":
                return String(Int(asset.width)).contains(value)
            case "height", "h":
                return String(Int(asset.height)).contains(value)
            case "type", "t":
                return asset.assetType.displayName.lowercased().contains(value)
            case "scale", "s":
                return asset.scaleString.lowercased().contains(value)
            case "name", "n":
                return asset.name.lowercased().contains(value)
            default:
                return asset.name.lowercased().contains(query.lowercased())
            }
        }
    }

    private func fuzzySearch(assets: [Asset], query: String) -> [Asset] {
        let lowercaseQuery = query.lowercased()

        // Score-based fuzzy matching
        let scored = assets.map { asset -> (Asset, Int) in
            let name = asset.name.lowercased()
            var score = 0

            // Exact match gets highest score
            if name == lowercaseQuery {
                score = 1000
            }
            // Prefix match
            else if name.hasPrefix(lowercaseQuery) {
                score = 500
            }
            // Contains match
            else if name.contains(lowercaseQuery) {
                score = 300
            }
            // Fuzzy match (allow missing/extra characters)
            else {
                score = fuzzyMatchScore(name: name, query: lowercaseQuery)
            }

            return (asset, score)
        }

        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private func fuzzyMatchScore(name: String, query: String) -> Int {
        var nameIndex = name.startIndex
        var queryIndex = query.startIndex
        var score = 0
        var consecutiveBonus = 0

        while nameIndex < name.endIndex && queryIndex < query.endIndex {
            if name[nameIndex] == query[queryIndex] {
                score += 10 + consecutiveBonus
                consecutiveBonus += 5
                queryIndex = query.index(after: queryIndex)
            } else {
                consecutiveBonus = 0
            }
            nameIndex = name.index(after: nameIndex)
        }

        // All query characters must be found
        return queryIndex == query.endIndex ? score : 0
    }

    // MARK: - Color Filtering

    private func filterByColor(assets: [Asset], targetColor: Color) -> [Asset] {
        let targetHSB = targetColor.hsb

        return assets.filter { asset in
            guard let dominantHSB = asset.dominantColorHSB else { return false }

            // Compare hue (with wraparound for red)
            var hueDiff = abs(dominantHSB.hue - targetHSB.hue)
            if hueDiff > 0.5 { hueDiff = 1.0 - hueDiff }

            let satDiff = abs(dominantHSB.saturation - targetHSB.saturation)
            let briDiff = abs(dominantHSB.brightness - targetHSB.brightness)

            // Weight hue more heavily, but also consider saturation and brightness
            let distance = hueDiff * 0.6 + satDiff * 0.2 + briDiff * 0.2
            return distance < colorFilterTolerance
        }
    }

    // MARK: - Sorting

    private func sortAssets(_ assets: [Asset]) -> [Asset] {
        switch sortOption {
        case .name:
            return assets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            return assets.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        case .type:
            return assets.sorted {
                if $0.assetType.rawValue != $1.assetType.rawValue {
                    return $0.assetType.rawValue < $1.assetType.rawValue
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .hue:
            return sortByHue(assets)
        }
    }

    private func sortByHue(_ assets: [Asset]) -> [Asset] {
        // Separate grayscale and colored images
        var colored: [(Asset, Double)] = []
        var grayscale: [Asset] = []

        for asset in assets {
            if let hsb = asset.dominantColorHSB {
                if hsb.saturation < 0.1 {
                    // Grayscale (low saturation)
                    grayscale.append(asset)
                } else {
                    colored.append((asset, hsb.hue))
                }
            } else {
                grayscale.append(asset)
            }
        }

        // Sort colored by hue (rainbow order)
        colored.sort { $0.1 < $1.1 }

        // Sort grayscale by brightness
        grayscale.sort {
            let b1 = $0.dominantColorHSB?.brightness ?? 0
            let b2 = $1.dominantColorHSB?.brightness ?? 0
            return b1 > b2
        }

        // Colored first, then grayscale at the end
        return colored.map { $0.0 } + grayscale
    }

    // MARK: - Group Name Extraction

    private func extractGroupName(from name: String) -> String {
        // Split by CamelCase - get the first "word" before a capital letter
        var result = ""
        for (index, char) in name.enumerated() {
            if index > 0 && char.isUppercase {
                break
            }
            result.append(char)
        }

        // If no split found or result is empty, use the whole name
        if result.isEmpty || result == name {
            // Try splitting by common separators as fallback
            if let firstPart = name.split(separator: "_").first ?? name.split(separator: "-").first {
                return String(firstPart)
            }
            return name
        }

        return result
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

    func copyAssetsToPasteboard(_ assets: [Asset]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if assets.count == 1, let asset = assets.first {
            // Single asset: copy as image data for direct pasting into apps
            var pasteboardItems: [NSPasteboardItem] = []
            let item = NSPasteboardItem()

            // Add TIFF representation (universal image format for pasteboard)
            if let tiffData = asset.image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }

            // Add PNG data
            if !asset.data.isEmpty {
                item.setData(asset.data, forType: .png)
            }

            // Add file URL
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(asset.filename)
            if let _ = try? asset.data.write(to: tempURL, options: .atomic) {
                item.setString(tempURL.absoluteString, forType: .fileURL)
            }

            pasteboardItems.append(item)
            pasteboard.writeObjects(pasteboardItems)
        } else {
            // Multiple assets: copy as file URLs
            let urls: [NSURL] = assets.compactMap { asset in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(asset.filename)

                do {
                    try asset.data.write(to: tempURL, options: .atomic)
                    return tempURL as NSURL
                } catch {
                    print("Failed to write temp file: \(error)")
                    return nil
                }
            }

            pasteboard.writeObjects(urls)
        }
    }

    func copySelectedAssets() {
        copyAssetsToPasteboard(selectedAssetObjects)
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
