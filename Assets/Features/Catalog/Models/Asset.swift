//
//  Asset.swift
//  Assets
//
//  Model representing an asset from a .car file
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Asset Model

struct Asset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let filename: String
    let image: NSImage
    let thumbnail: NSImage
    let data: Data
    let scale: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isVector: Bool
    let assetType: AssetType
    /// Lowercased name, precomputed once so search passes never re-lowercase per asset per call
    let searchKey: String

    enum AssetType: Int, CaseIterable {
        case image = 0
        case imageSet
        case icon
        case color
        case vector
        case data
        case unknown

        var displayName: String {
            switch self {
            case .image: return "Image"
            case .imageSet: return "Image Set"
            case .icon: return "Icon"
            case .color: return "Color"
            case .vector: return "Vector"
            case .data: return "Data"
            case .unknown: return "Unknown"
            }
        }

        var iconName: String {
            switch self {
            case .image, .imageSet: return "photo"
            case .icon: return "app"
            case .color: return "paintpalette"
            case .vector: return "pencil.and.outline"
            case .data: return "doc"
            case .unknown: return "questionmark.square"
            }
        }
    }

    init(from dictionary: [String: Any]) {
        self.name = dictionary["name"] as? String ?? "Unknown"
        self.searchKey = self.name.lowercased()
        self.filename = dictionary["filename"] as? String ?? "unknown.png"
        self.image = dictionary["image"] as? NSImage ?? NSImage()
        self.thumbnail = dictionary["thumbnail"] as? NSImage ?? NSImage()
        self.data = dictionary["data"] as? Data ?? Data()
        self.scale = dictionary["scale"] as? CGFloat ?? 1.0
        self.width = dictionary["width"] as? CGFloat ?? 0
        self.height = dictionary["height"] as? CGFloat ?? 0
        self.isVector = dictionary["isVector"] as? Bool ?? false

        if let typeRaw = dictionary["assetType"] as? Int {
            self.assetType = AssetType(rawValue: typeRaw) ?? .unknown
        } else {
            self.assetType = .unknown
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }

    /// Formatted size string
    var sizeString: String {
        "\(Int(width)) × \(Int(height))"
    }

    /// Scale suffix for display
    var scaleString: String {
        scale > 1 ? "@\(Int(scale))x" : "@1x"
    }

    /// File size formatted
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

// MARK: - Asset Category (for Sidebar)

struct AssetCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let iconName: String
    let assetTypes: Set<Asset.AssetType>
    var count: Int = 0

    static let all = AssetCategory(
        name: "All Assets",
        iconName: "square.grid.2x2",
        assetTypes: Set(Asset.AssetType.allCases)
    )

    static let images = AssetCategory(
        name: "Images",
        iconName: "photo",
        assetTypes: [.image, .imageSet]
    )

    static let vectors = AssetCategory(
        name: "Vectors",
        iconName: "pencil.and.outline",
        assetTypes: [.vector]
    )

    static let icons = AssetCategory(
        name: "Icons",
        iconName: "app",
        assetTypes: [.icon]
    )

    static let colors = AssetCategory(
        name: "Colors",
        iconName: "paintpalette",
        assetTypes: [.color]
    )

    static let defaultCategories: [AssetCategory] = [.all, .images, .vectors, .icons, .colors]
}

// MARK: - Asset Group (for Sidebar)

struct AssetGroup: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let count: Int
}

// MARK: - Color Analysis

extension Asset {
    /// Dominant color in HSB, averaged from pixel samples decoded out of the
    /// immutable `data` bytes — never from `thumbnail`/`image`: this runs on
    /// background filter threads while the main thread draws those same
    /// NSImage instances, and a single NSImage is not safe for concurrent use.
    /// Expensive on every call (decode + per-pixel sampling) — callers
    /// should go through `AssetFilterCaches.dominantColorHSB(for:epoch:)`.
    var dominantColorHSB: (hue: Double, saturation: Double, brightness: Double)? {
        guard let bitmap = Self.sampleBitmap(from: data) else {
            return nil
        }

        // Sample colors from the image
        var totalHue: Double = 0
        var totalSat: Double = 0
        var totalBri: Double = 0
        var sampleCount: Double = 0

        let sampleStep = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 10)

        for x in stride(from: 0, to: bitmap.pixelsWide, by: sampleStep) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: sampleStep) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }

                // Skip transparent pixels
                if color.alphaComponent < 0.5 { continue }

                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

                totalHue += Double(h)
                totalSat += Double(s)
                totalBri += Double(b)
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }

        return (
            hue: totalHue / sampleCount,
            saturation: totalSat / sampleCount,
            brightness: totalBri / sampleCount
        )
    }

    /// Bitmap decoded from raw asset bytes: PNG decodes directly; SVG
    /// rasterizes through a locally created NSImage so no instance shared
    /// with the main thread is ever touched.
    private static func sampleBitmap(from data: Data) -> NSBitmapImageRep? {
        if let bitmap = NSBitmapImageRep(data: data) {
            return bitmap
        }
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: tiffData)
    }
}

// MARK: - Color Extension for HSB

extension Color {
    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let nsColor = NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (hue: Double(h), saturation: Double(s), brightness: Double(b))
    }
}

// MARK: - UTType Extension

extension UTType {
    static var assetCatalog: UTType {
        UTType(importedAs: "com.apple.assetcatalog.compiled")
    }

    static var bundle: UTType {
        UTType(filenameExtension: "bundle") ?? .package
    }

    static var appBundle: UTType {
        UTType(filenameExtension: "app") ?? .applicationBundle
    }
}

// MARK: - Transferable

extension Asset: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Concrete file URL first: Chromium-based receivers (Figma, Slack, VS Code)
        // read only NSPasteboardTypeFileURL from drops and never resolve the file
        // promises that FileRepresentation vends on the macOS drag pasteboard.
        // The exporter runs lazily at fulfillment time — once per drag, not at render.
        ProxyRepresentation(exporting: { asset in
            try asset.writeTemporaryFile()
        })

        DataRepresentation(exportedContentType: .svg) { $0.data }
            .exportingCondition { $0.isVector }

        DataRepresentation(exportedContentType: .png) { $0.data }
            .exportingCondition { !$0.isVector }
    }
}
