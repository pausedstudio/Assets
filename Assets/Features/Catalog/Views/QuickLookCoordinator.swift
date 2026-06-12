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

    let responder =
      contentView.subviews.first { $0 is QuickLookResponderView }
      ?? {
        let view = QuickLookResponderView()
        view.frame = .zero
        contentView.addSubview(view)
        return view
      }()

    // Always re-assert first responder: QLPreviewPanel finds its controller by
    // walking the responder chain, which would miss this view when e.g. the
    // list's NSTableView has focus.
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
  @State private var hostWindow: NSWindow?

  func body(content: Content) -> some View {
    content
      .background(WindowReader(window: $hostWindow))
      .onAppear {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
          // Only handle keys aimed at this document window while it's key
          guard let host = hostWindow, event.window === host, host.isKeyWindow else {
            return event
          }

          // Don't intercept if a text field has focus
          if host.firstResponder is NSTextView { return event }

          // Let command/option/control shortcuts reach the system
          if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            return event
          }

          switch event.keyCode {
          case 49:  // spacebar
            QuickLookCoordinator.shared.toggle(asset: selectedAsset)
            return nil
          case 53:  // escape
            if let panel = QLPreviewPanel.shared(), panel.isVisible { return event }
            if !viewModel.searchText.isEmpty {
              viewModel.searchText = ""
              return nil
            }
            return event
          case 123, 124, 125, 126:  // arrows
            return handleArrow(event)
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

  // MARK: - Arrow Navigation

  private func handleArrow(_ event: NSEvent) -> NSEvent? {
    let isVertical = event.keyCode == 125 || event.keyCode == 126
    let isForward = event.keyCode == 124 || event.keyCode == 125
    let isShiftHeld = event.modifierFlags.contains(.shift)

    switch viewModel.viewMode {
    case .list:
      // Horizontal arrows have no meaning in a list
      guard isVertical else { return event }
      let step = isForward ? 1 : -1

      if let panel = QLPreviewPanel.shared(), panel.isVisible {
        // Table can't navigate while the panel is open; drive selection directly
        if isShiftHeld { extendSelection(by: step) } else { moveSelection(by: step) }
        return nil
      }
      if event.window?.firstResponder is NSTableView {
        // Native Table navigation: correct order, auto-scroll, shift-extend
        return event
      }
      if isShiftHeld { extendSelection(by: step) } else { moveSelection(by: step) }
      return nil

    case .grid:
      let step: Int
      if isVertical {
        step = isForward ? viewModel.gridColumnCount : -viewModel.gridColumnCount
      } else {
        step = isForward ? 1 : -1
      }
      if isShiftHeld { extendSelection(by: step) } else { moveSelection(by: step) }
      return nil
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
    viewModel.selectionAnchorID = asset.id

    // Update Quick Look if panel is open
    if let panel = QLPreviewPanel.shared(), panel.isVisible {
      QuickLookCoordinator.shared.preview(asset: asset)
    }
  }

  /// Extends the range selection from the anchor; the cursor follows the extension edge.
  private func extendSelection(by offset: Int) {
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
    let target = assets[newIndex]
    viewModel.selectRange(to: target)
    selectedAsset = target
  }
}

// MARK: - Window Reader

/// Captures the NSWindow hosting a SwiftUI view so event monitors can scope to it
private struct WindowReader: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      window = nsView.window
    }
  }
}

extension View {
  func quickLook(asset: Binding<Asset?>, viewModel: CatalogViewModel) -> some View {
    modifier(QuickLookModifier(selectedAsset: asset, viewModel: viewModel))
  }
}
