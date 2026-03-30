//
//  QuickLookCoordinator.swift
//  Assets
//
//  Manages QLPreviewPanel for spacebar Quick Look of assets
//

import AppKit
import Quartz
import SwiftUI

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  static let shared = QuickLookCoordinator()

  private var previewURL: URL?
  private var sourceRect: NSRect = .zero
  private var sourceImage: NSImage?

  // MARK: - Public

  /// Call from grid items to register their screen-space frame
  func setSourceFrame(_ rect: NSRect, image: NSImage?) {
    sourceRect = rect
    sourceImage = image
  }

  func preview(asset: Asset) {
    let url = writeTempFile(for: asset)
    previewURL = url
    sourceImage = asset.thumbnail
    ensureResponder()

    if let panel = QLPreviewPanel.shared() {
      if panel.isVisible {
        panel.reloadData()
      } else {
        panel.makeKeyAndOrderFront(nil)
        centerPanel(panel)
      }
    }
  }

  private func centerPanel(_ panel: QLPreviewPanel) {
    guard
      let window = NSApp.windows.first(where: { $0 != panel && $0.isVisible && !$0.isMiniaturized })
    else { return }
    let windowFrame = window.frame
    let panelFrame = panel.frame
    let x = windowFrame.midX - panelFrame.width / 2
    let y = windowFrame.midY - panelFrame.height / 2
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  func toggle(asset: Asset?) {
    guard let panel = QLPreviewPanel.shared() else { return }

    if panel.isVisible {
      panel.orderOut(nil)
    } else if let asset {
      preview(asset: asset)
    }
  }

  // MARK: - Responder

  private func ensureResponder() {
    guard let window = NSApp.keyWindow,
      let contentView = window.contentView
    else { return }

    // Check if we already installed one
    if contentView.subviews.contains(where: { $0 is QuickLookResponderView }) { return }

    let responder = QuickLookResponderView()
    responder.frame = .zero
    contentView.addSubview(responder)
    window.makeFirstResponder(responder)
  }

  // MARK: - Temp File

  private func writeTempFile(for asset: Asset) -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("AssetQuickLook", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let url = dir.appendingPathComponent("\(asset.name).png")

    if let tiff = asset.image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    {
      try? png.write(to: url, options: .atomic)
    }

    return url
  }

  // MARK: - QLPreviewPanelDataSource

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    previewURL != nil ? 1 : 0
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    previewURL as? NSURL
  }

  // MARK: - QLPreviewPanelDelegate

  func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!)
    -> NSRect
  {
    guard sourceRect != .zero else { return .zero }
    return sourceRect
  }

  func previewPanel(
    _ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!,
    contentRect: UnsafeMutablePointer<NSRect>!
  ) -> Any! {
    sourceImage
  }

  func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
    false
  }
}

// MARK: - QLPreviewPanel Responder Bridge

final class QuickLookResponderView: NSView {
  override var acceptsFirstResponder: Bool { true }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    true
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = QuickLookCoordinator.shared
    panel.delegate = QuickLookCoordinator.shared
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = nil
    panel.delegate = nil
  }
}

// MARK: - SwiftUI Modifier

/// Installs a spacebar event monitor, arrow key navigation, and QLPreviewPanel responder
struct QuickLookModifier: ViewModifier {
  @Binding var selectedAsset: Asset?
  let viewModel: CatalogViewModel
  @State private var monitor: Any?

  func body(content: Content) -> some View {
    content
      .onAppear {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
          // Don't intercept if a text field has focus
          if NSApp.keyWindow?.firstResponder is NSTextView { return event }

          switch event.keyCode {
          case 49:  // spacebar
            QuickLookCoordinator.shared.toggle(asset: selectedAsset)
            return nil
          case 123:  // left arrow
            moveSelection(by: -1)
            return nil
          case 124:  // right arrow
            moveSelection(by: 1)
            return nil
          case 125:  // down arrow
            moveSelection(by: columnsInGrid())
            return nil
          case 126:  // up arrow
            moveSelection(by: -columnsInGrid())
            return nil
          default:
            return event
          }
        }
      }
      .onDisappear {
        if let monitor {
          NSEvent.removeMonitor(monitor)
        }
        monitor = nil
      }
  }

  private func moveSelection(by offset: Int) {
    let assets = viewModel.filteredAssets
    guard !assets.isEmpty else { return }

    let currentIndex: Int
    if let selected = selectedAsset,
      let idx = assets.firstIndex(where: { $0.id == selected.id })
    {
      currentIndex = idx
    } else {
      currentIndex = -1
    }

    let newIndex = max(0, min(assets.count - 1, currentIndex + offset))
    let asset = assets[newIndex]
    selectedAsset = asset
    viewModel.selectedAssets = [asset.id]

    // Update Quick Look if panel is open
    if let panel = QLPreviewPanel.shared(), panel.isVisible {
      QuickLookCoordinator.shared.preview(asset: asset)
    }
  }

  /// Estimate grid columns from window width (matches grid's adaptive 120-180pt items)
  private func columnsInGrid() -> Int {
    guard let window = NSApp.keyWindow else { return 4 }
    // Rough: content area minus sidebar, divided by item size + spacing
    let availableWidth = window.contentView?.bounds.width ?? 600
    let gridWidth = max(availableWidth - 240, 300)  // subtract sidebar estimate
    return max(1, Int(gridWidth / 132))  // 120 item + 12 spacing
  }
}

extension View {
  func quickLook(asset: Binding<Asset?>, viewModel: CatalogViewModel) -> some View {
    modifier(QuickLookModifier(selectedAsset: asset, viewModel: viewModel))
  }
}
