//
//  AssetFilterEngine.swift
//  Assets
//
//  Pure filter/sort pipeline for CatalogViewModel, executed off the main thread
//

import AppKit
import Foundation
import os

// MARK: - Filter Caches

/// Lock-guarded caches shared between (possibly overlapping) background filter
/// tasks — a cancelled task can still be mid-compute when its successor starts,
/// so every access takes the lock. The epoch guards against a stale task
/// persisting results computed from a previous catalog's assets.
final class AssetFilterCaches: @unchecked Sendable {
    typealias HSB = (hue: Double, saturation: Double, brightness: Double)

    private let lock = NSLock()
    private var epoch = 0
    private var sortedBases: [CatalogViewModel.SortOption: [Asset]] = [:]
    private var dominantColors: [Asset.ID: HSB?] = [:]

    var currentEpoch: Int {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    /// Invalidates everything; call when a new catalog loads.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        epoch += 1
        sortedBases.removeAll()
        dominantColors.removeAll()
    }

    func sortedBase(for option: CatalogViewModel.SortOption, epoch requestEpoch: Int) -> [Asset]? {
        lock.lock()
        defer { lock.unlock() }
        guard requestEpoch == epoch else { return nil }
        return sortedBases[option]
    }

    func storeSortedBase(_ base: [Asset], for option: CatalogViewModel.SortOption, epoch requestEpoch: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard requestEpoch == epoch else { return }
        sortedBases[option] = base
    }

    /// Memoized dominant color: the pixel sampling behind `Asset.dominantColorHSB`
    /// costs ~1ms per call, so it runs at most once per asset. `nil` results
    /// (no opaque pixels) are cached too.
    func dominantColorHSB(for asset: Asset, epoch requestEpoch: Int) -> HSB? {
        lock.lock()
        if requestEpoch == epoch, let cached = dominantColors[asset.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Never hold the lock across the pixel sampling
        let computed = asset.dominantColorHSB

        lock.lock()
        if requestEpoch == epoch {
            dominantColors[asset.id] = computed
        }
        lock.unlock()
        return computed
    }
}

// MARK: - Filter Engine

/// Stateless filter/sort pipeline mirroring the original synchronous
/// `filterAssets()` semantics: group/category filter → smart search → color
/// filter, with the sort order applied on top (search relevance ranking is
/// intentionally discarded, as before). Every pass checks `Task.isCancelled`
/// periodically and returns `nil` when cancelled.
enum AssetFilterEngine {
    /// Immutable snapshot of every filter input, captured on the main thread
    /// so the background pass never reads observable state.
    struct Request: @unchecked Sendable {
        let assets: [Asset]
        let searchText: String
        let groupName: String?
        let categoryTypes: Set<Asset.AssetType>?
        let sortOption: CatalogViewModel.SortOption
        let colorTarget: AssetFilterCaches.HSB?
        let colorTolerance: Double
        let cacheEpoch: Int
    }

    private static let signposter = OSSignposter(subsystem: "com.paused.Assets", category: "perf")

    /// Assets processed between cancellation checks in cheap per-asset passes
    private static let cancellationStride = 512
    /// Stride for passes that may sample pixels (~1ms/asset on a cold cache)
    private static let expensiveCancellationStride = 16

    static func filteredAssets(for request: Request, caches: AssetFilterCaches) -> [Asset]? {
        let state = signposter.beginInterval("filterAssets", id: signposter.makeSignpostID())
        var resultCount = -1  // -1 in the signpost = cancelled
        defer {
            signposter.endInterval("filterAssets", state, "in: \(request.assets.count) out: \(resultCount)")
        }

        // Filter from a presorted base so the ICU (or pixel-sampling) sort runs
        // once per (catalog, sort option) instead of on every keystroke.
        var result: [Asset]
        if let base = caches.sortedBase(for: request.sortOption, epoch: request.cacheEpoch) {
            result = base
        } else {
            guard let sorted = sortAssets(request.assets, by: request.sortOption,
                                          epoch: request.cacheEpoch, caches: caches) else { return nil }
            caches.storeSortedBase(sorted, for: request.sortOption, epoch: request.cacheEpoch)
            result = sorted
        }
        if Task.isCancelled { return nil }

        // Filter by group (takes precedence over category)
        if let groupName = request.groupName {
            result = result.filter { extractGroupName(from: $0.name) == groupName }
        } else if let categoryTypes = request.categoryTypes {
            result = result.filter { categoryTypes.contains($0.assetType) }
        }
        if Task.isCancelled { return nil }

        // Filter by search (smart search)
        if !request.searchText.isEmpty {
            guard let matches = smartSearch(assets: result, query: request.searchText) else { return nil }
            // Re-impose the presorted order: the original pipeline sorted after
            // searching, which discarded the search's relevance ranking.
            let matchedIDs = Set(matches.map(\.id))
            result = result.filter { matchedIDs.contains($0.id) }
        }

        // Filter by color
        if let target = request.colorTarget {
            guard let colorFiltered = filterByColor(assets: result, target: target,
                                                    tolerance: request.colorTolerance,
                                                    epoch: request.cacheEpoch, caches: caches) else { return nil }
            result = colorFiltered
        }

        resultCount = result.count
        return result
    }

    // MARK: - Smart Search

    private static func smartSearch(assets: [Asset], query: String) -> [Asset]? {
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

    private static func regexSearch(assets: [Asset], pattern: String) -> [Asset]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            // Fall back to fuzzy search if regex is invalid
            return fuzzySearch(assets: assets, query: pattern)
        }

        var result: [Asset] = []
        for (index, asset) in assets.enumerated() {
            if index % cancellationStride == 0 && Task.isCancelled { return nil }
            let range = NSRange(asset.name.startIndex..., in: asset.name)
            if regex.firstMatch(in: asset.name, options: [], range: range) != nil {
                result.append(asset)
            }
        }
        return result
    }

    private static func metadataSearch(assets: [Asset], query: String) -> [Asset]? {
        let parts = query.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return fuzzySearch(assets: assets, query: query)
        }

        let field = String(parts[0]).lowercased()
        let value = String(parts[1]).lowercased()
        let lowercaseQuery = query.lowercased()

        var result: [Asset] = []
        for (index, asset) in assets.enumerated() {
            if index % cancellationStride == 0 && Task.isCancelled { return nil }
            let matches: Bool
            switch field {
            case "size", "width", "w":
                matches = String(Int(asset.width)).contains(value)
            case "height", "h":
                matches = String(Int(asset.height)).contains(value)
            case "type", "t":
                matches = asset.assetType.displayName.lowercased().contains(value)
            case "scale", "s":
                matches = asset.scaleString.lowercased().contains(value)
            case "name", "n":
                matches = asset.searchKey.contains(value)
            default:
                matches = asset.searchKey.contains(lowercaseQuery)
            }
            if matches { result.append(asset) }
        }
        return result
    }

    private static func fuzzySearch(assets: [Asset], query: String) -> [Asset]? {
        let lowercaseQuery = query.lowercased()

        // Score-based fuzzy matching
        var scored: [(asset: Asset, score: Int)] = []
        scored.reserveCapacity(assets.count)

        for (index, asset) in assets.enumerated() {
            if index % cancellationStride == 0 && Task.isCancelled { return nil }
            let name = asset.searchKey
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

            if score > 0 {
                scored.append((asset, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .map { $0.asset }
    }

    private static func fuzzyMatchScore(name: String, query: String) -> Int {
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

    private static func filterByColor(assets: [Asset], target: AssetFilterCaches.HSB,
                                      tolerance: Double, epoch: Int,
                                      caches: AssetFilterCaches) -> [Asset]? {
        var result: [Asset] = []
        for (index, asset) in assets.enumerated() {
            if index % expensiveCancellationStride == 0 && Task.isCancelled { return nil }
            guard let dominantHSB = caches.dominantColorHSB(for: asset, epoch: epoch) else { continue }

            // Compare hue (with wraparound for red)
            var hueDiff = abs(dominantHSB.hue - target.hue)
            if hueDiff > 0.5 { hueDiff = 1.0 - hueDiff }

            let satDiff = abs(dominantHSB.saturation - target.saturation)
            let briDiff = abs(dominantHSB.brightness - target.brightness)

            // Weight hue more heavily, but also consider saturation and brightness
            let distance = hueDiff * 0.6 + satDiff * 0.2 + briDiff * 0.2
            if distance < tolerance { result.append(asset) }
        }
        return result
    }

    // MARK: - Sorting

    private static func sortAssets(_ assets: [Asset], by option: CatalogViewModel.SortOption,
                                   epoch: Int, caches: AssetFilterCaches) -> [Asset]? {
        switch option {
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
            return sortByHue(assets, epoch: epoch, caches: caches)
        }
    }

    private static func sortByHue(_ assets: [Asset], epoch: Int, caches: AssetFilterCaches) -> [Asset]? {
        // Separate grayscale and colored images, decorating with the sort key
        // so comparators never recompute the dominant color
        var colored: [(asset: Asset, hue: Double)] = []
        var grayscale: [(asset: Asset, brightness: Double)] = []

        for (index, asset) in assets.enumerated() {
            if index % expensiveCancellationStride == 0 && Task.isCancelled { return nil }
            if let hsb = caches.dominantColorHSB(for: asset, epoch: epoch) {
                if hsb.saturation < 0.1 {
                    // Grayscale (low saturation)
                    grayscale.append((asset, hsb.brightness))
                } else {
                    colored.append((asset, hsb.hue))
                }
            } else {
                grayscale.append((asset, 0))
            }
        }

        // Sort colored by hue (rainbow order)
        colored.sort { $0.hue < $1.hue }

        // Sort grayscale by brightness
        grayscale.sort { $0.brightness > $1.brightness }

        // Colored first, then grayscale at the end
        return colored.map { $0.asset } + grayscale.map { $0.asset }
    }

    // MARK: - Group Name Extraction

    static func extractGroupName(from name: String) -> String {
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
}
