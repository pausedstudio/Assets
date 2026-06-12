//
//  AssetTempFiles.swift
//  Assets
//
//  Temporary file management for copy/drag exports
//

import Foundation

enum AssetTempFiles {
    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AssetsExport", isDirectory: true)

    /// Fresh unique dir per copy/drag operation — no collisions, no stale overwrites.
    static func makeUniqueDirectory() throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Remove subdirs older than 1h (a prior paste's Finder copy may still be in flight).
    static func cleanUpStale(olderThan age: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-age)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        for child in children {
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: child)
        }
    }
}

extension Asset {
    /// Writes `data` to `<unique dir>/<filename>`; returns the URL.
    func writeTemporaryFile(in directory: URL? = nil) throws -> URL {
        let dir = try directory ?? AssetTempFiles.makeUniqueDirectory()
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
