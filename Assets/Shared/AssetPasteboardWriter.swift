//
//  AssetPasteboardWriter.swift
//  Assets
//
//  Pasteboard writing for asset copy operations
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum AssetPasteboardWriter {
    static func copy(_ assets: [Asset], to pasteboard: NSPasteboard = .general) {
        guard !assets.isEmpty else { return }

        if assets.count == 1, let asset = assets.first {
            copySingle(asset, to: pasteboard)
        } else {
            copyMultiple(assets, to: pasteboard)
        }
    }

    static func copyNames(of assets: [Asset], to pasteboard: NSPasteboard = .general) {
        guard !assets.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(assets.map(\.name).joined(separator: "\n"), forType: .string)
    }

    // MARK: - Single Asset

    private static func copySingle(_ asset: Asset, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()

        if asset.isVector {
            // Type order = writer preference: SVG text first so vector-aware
            // receivers take editable vectors; raster TIFF is the last resort.
            if let svgText = String(data: asset.data, encoding: .utf8) {
                item.setString(svgText, forType: .string)
            }
            item.setData(asset.data, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
            if let url = try? asset.writeTemporaryFile() {
                item.setData(url.dataRepresentation, forType: .fileURL)
            }
            if let tiffData = asset.image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
        } else {
            if !asset.data.isEmpty {
                item.setData(asset.data, forType: .png)
            }
            if let tiffData = asset.image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
            if let url = try? asset.writeTemporaryFile() {
                item.setData(url.dataRepresentation, forType: .fileURL)
            }
        }

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    // MARK: - Multiple Assets

    private static func copyMultiple(_ assets: [Asset], to pasteboard: NSPasteboard) {
        guard let directory = try? AssetTempFiles.makeUniqueDirectory() else { return }

        var usedNames: Set<String> = []
        let urls: [NSURL] = assets.compactMap { asset in
            let filename = dedupedFilename(asset.filename, used: &usedNames)
            let url = directory.appendingPathComponent(filename)
            guard (try? asset.data.write(to: url, options: .atomic)) != nil else { return nil }
            return url as NSURL
        }

        // Only clear once there is something to write — a failed temp write
        // must never destroy the user's existing clipboard.
        guard !urls.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls)
    }

    /// Case-insensitive filename dedupe: `name.png`, `name 2.png`, `name 3.png`…
    private static func dedupedFilename(_ filename: String, used: inout Set<String>) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = filename
        var counter = 2
        while used.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
