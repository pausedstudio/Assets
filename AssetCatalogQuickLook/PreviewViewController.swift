//
//  PreviewViewController.swift
//  AssetCatalogQuickLook
//
//  QuickLook preview for .car files
//

import AssetCatalogKit
import Cocoa
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

  private var assets: [[String: Any]] = []
  private var totalCount: Int = 0

  override var nibName: NSNib.Name? { nil }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    view.wantsLayer = true
  }

  func preparePreviewOfFile(at url: URL) async throws {
    let carURL = Self.findCarFile(at: url)

    let reader = AssetCatalogReader(fileURL: carURL)
    reader.readSync(withMaxCount: 50)
    assets = reader.assets ?? []
    totalCount = Int(reader.totalNumberOfAssets)

    await MainActor.run {
      buildGrid()
    }
  }

  // MARK: - Grid

  private func buildGrid() {
    view.subviews.forEach { $0.removeFromSuperview() }

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    view.addSubview(scrollView)

    let summaryLabel = NSTextField(labelWithString: "")
    summaryLabel.translatesAutoresizingMaskIntoConstraints = false
    summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
    summaryLabel.textColor = .secondaryLabelColor
    summaryLabel.alignment = .center
    view.addSubview(summaryLabel)

    if totalCount > assets.count {
      summaryLabel.stringValue = "Showing \(assets.count) of \(totalCount) assets"
    } else {
      summaryLabel.stringValue = "\(totalCount) assets"
    }

    let gridView = NSView()
    gridView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = gridView

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      scrollView.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -8),
      summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      summaryLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
      summaryLabel.heightAnchor.constraint(equalToConstant: 20),
    ])

    let itemSize: CGFloat = 72
    let spacing: CGFloat = 8
    let margin: CGFloat = 12
    let viewWidth = max(view.bounds.width - margin * 2, 300)
    let columns = max(1, Int(viewWidth / (itemSize + spacing)))

    var x: CGFloat = margin
    var y: CGFloat = margin
    var maxY: CGFloat = 0

    for (index, asset) in assets.enumerated() {
      guard let imageRep = asset["imagerep"] as? NSImageRep,
        let name = asset["name"] as? String
      else { continue }

      let itemView = createItemView(imageRep: imageRep, name: name, size: itemSize)
      itemView.frame = NSRect(x: x, y: y, width: itemSize, height: itemSize + 18)
      gridView.addSubview(itemView)

      maxY = max(maxY, y + itemSize + 18 + spacing)

      if (index + 1) % columns == 0 {
        x = margin
        y += itemSize + 18 + spacing
      } else {
        x += itemSize + spacing
      }
    }

    gridView.frame = NSRect(x: 0, y: 0, width: viewWidth, height: maxY + margin)
  }

  private func createItemView(imageRep: NSImageRep, name: String, size: CGFloat) -> NSView {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size + 18))

    let bgView = NSView(frame: NSRect(x: 2, y: 20, width: size - 4, height: size - 4))
    bgView.wantsLayer = true
    bgView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    bgView.layer?.cornerRadius = 4
    container.addSubview(bgView)

    let imageView = NSImageView(frame: NSRect(x: 4, y: 22, width: size - 8, height: size - 8))
    let image = NSImage(size: imageRep.size)
    image.addRepresentation(imageRep)
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    container.addSubview(imageView)

    let label = NSTextField(labelWithString: name)
    label.frame = NSRect(x: 0, y: 0, width: size, height: 14)
    label.font = .systemFont(ofSize: 9)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingMiddle
    container.addSubview(label)

    return container
  }

  // MARK: - Bundle Support

  private static func findCarFile(at url: URL) -> URL {
    if url.pathExtension == "car" { return url }

    let candidates = [
      url.appendingPathComponent("Contents/Resources/Assets.car"),
      url.appendingPathComponent("Assets.car"),
      url.appendingPathComponent("Contents/Resources/Images.car"),
    ]

    for candidate in candidates {
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    if let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles])
    {
      for case let fileURL as URL in enumerator where fileURL.pathExtension == "car" {
        return fileURL
      }
    }

    return url
  }
}
