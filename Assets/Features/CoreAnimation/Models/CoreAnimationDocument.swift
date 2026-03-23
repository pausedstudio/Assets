//
//  CoreAnimationDocument.swift
//  Assets
//
//  Document model for .caar and .ca Core Animation files
//

import SwiftUI
import UniformTypeIdentifiers

struct CoreAnimationDocument: FileDocument {
  var package: CAPackage?

  init() {}

  static let readableContentTypes = [
    UTType(importedAs: "com.apple.coreanimation-bundle"),
    UTType(importedAs: "com.apple.coreanimation-archive"),
  ]

  init(configuration: ReadConfiguration) throws {
    if configuration.file.filename?.hasSuffix(".caar") == true
      || configuration.file.filename?.hasSuffix(".caml") == true
    {
      guard let data = configuration.file.regularFileContents else {
        throw CocoaError(.fileReadCorruptFile)
      }

      let package =
        try CAPackage.package(
          with: data,
          type: kCAPackageTypeArchive,
          options: nil
        ) as? CAPackage

      guard let package = package else {
        throw CocoaError(.fileReadCorruptFile)
      }

      self.package = package
    } else if configuration.file.filename?.hasSuffix(".ca") == true {
      let tempParent = FileManager.default.temporaryDirectory
      let tempFolder = tempParent.appendingPathComponent(UUID().uuidString + ".ca")
      try configuration.file.write(to: tempFolder, originalContentsURL: nil)

      let package =
        try CAPackage.package(
          withContentsOf: tempFolder,
          type: kCAPackageTypeCAMLBundle,
          options: nil
        ) as? CAPackage

      guard let package = package else {
        throw CocoaError(.fileReadCorruptFile)
      }

      self.package = package
    }
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    .init()
  }
}
