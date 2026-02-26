//
//  ImageExporter.swift
//  AssetCatalogKit
//
//  Exports assets to a directory
//

import Cocoa

/// Keys matching the Objective-C constants in AssetCatalogReader
public enum AssetKeys {
    public static let name = "name"
    public static let image = "image"
    public static let thumbnail = "thumbnail"
    public static let filename = "filename"
    public static let data = "data"
    public static let imageRep = "imagerep"
    public static let scale = "scale"
    public static let isVector = "isVector"
    public static let assetType = "assetType"
    public static let width = "width"
    public static let height = "height"
}

public struct ImageExporter: Sendable {
    public let images: [AssetExportItem]

    public struct AssetExportItem: Sendable {
        public let filename: String
        public let data: Data

        public init(filename: String, data: Data) {
            self.filename = filename
            self.data = data
        }
    }

    public init(images: [[String: Any]]) {
        self.images = images.compactMap { dict in
            guard let filename = dict[AssetKeys.filename] as? String,
                  let data = dict[AssetKeys.data] as? Data else { return nil }
            return AssetExportItem(filename: filename, data: data)
        }
    }

    public init(items: [AssetExportItem]) {
        self.images = items
    }

    /// Export images asynchronously
    public func export(toDirectoryAt url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let items = self.images
            let directory = url

            DispatchQueue.global(qos: .userInitiated).async {
                for item in items {
                    let targetPath = Self.nextAvailablePath(
                        directory: directory,
                        filename: item.filename
                    )

                    do {
                        try item.data.write(to: targetPath, options: .atomic)
                    } catch {
                        print("ERROR: Unable to write \(item.filename): \(error)")
                    }
                }

                continuation.resume()
            }
        }
    }

    /// Export images with completion handler
    public func export(toDirectoryAt url: URL, completionHandler: (@Sendable () -> Void)? = nil) {
        let items = self.images
        let directory = url

        DispatchQueue.global(qos: .userInitiated).async {
            for item in items {
                let targetPath = Self.nextAvailablePath(
                    directory: directory,
                    filename: item.filename
                )

                do {
                    try item.data.write(to: targetPath, options: .atomic)
                } catch {
                    print("ERROR: Unable to write \(item.filename): \(error)")
                }
            }

            DispatchQueue.main.async {
                completionHandler?()
            }
        }
    }

    /// Find next available path, appending _1, _2, etc. if file exists
    private static func nextAvailablePath(directory: URL, filename: String) -> URL {
        let fileManager = FileManager.default
        let baseURL = directory.appendingPathComponent(filename)
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension

        var counter = 1
        var targetURL = baseURL

        while fileManager.fileExists(atPath: targetURL.path) && counter < 1000 {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            targetURL = directory.appendingPathComponent(newName)
            counter += 1
        }

        return targetURL
    }
}
