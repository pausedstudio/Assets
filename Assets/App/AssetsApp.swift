//
//  AssetsApp.swift
//  Assets
//
//  Main app entry point - document-based app for viewing .car files
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct AssetsApp: App {
  var body: some Scene {
    DocumentGroup(viewing: AssetCatalogDocument.self) { configuration in
      ContentView(document: configuration.document)
    }
    .commands {
      // Remove New menu item (read-only app)
      CommandGroup(replacing: .newItem) {}

      AssetMenuCommands()
    }

    DocumentGroup(newDocument: CoreAnimationDocument()) { file in
      CoreAnimationView(document: file.$document)
    }

    Settings {
      SettingsView()
    }
  }
}

// MARK: - Asset Catalog Document

final class AssetCatalogDocument: ReferenceFileDocument {
  // Support .car files, .bundle, and .app bundles
  static var readableContentTypes: [UTType] {
    [.assetCatalog, .bundle, .appBundle, .package, .applicationBundle]
  }

  let fileURL: URL
  let viewModel: CatalogViewModel

  required init(configuration: ReadConfiguration) throws {
    let tempDir = FileManager.default.temporaryDirectory
    let filename = configuration.file.preferredFilename ?? "catalog.car"

    // Handle directory-based files (bundles)
    if configuration.file.isDirectory {
      // For bundles, we need to write the whole directory structure
      let tempURL = tempDir.appendingPathComponent(filename)
      try? FileManager.default.removeItem(at: tempURL)
      try configuration.file.write(to: tempURL, options: .atomic, originalContentsURL: nil)
      self.fileURL = tempURL
    } else if let fileContents = configuration.file.regularFileContents {
      // For regular .car files
      let tempURL = tempDir.appendingPathComponent(filename)
      try? fileContents.write(to: tempURL)
      self.fileURL = tempURL
    } else {
      throw CocoaError(.fileReadCorruptFile)
    }

    self.viewModel = CatalogViewModel()
  }

  // Direct initialization with URL (for testing)
  init(fileURL: URL) {
    self.fileURL = fileURL
    self.viewModel = CatalogViewModel()
  }

  func snapshot(contentType: UTType) throws -> Data {
    // Read-only, return empty data
    Data()
  }

  func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
    // Read-only document
    throw CocoaError(.fileWriteUnknown)
  }
}
