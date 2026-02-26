//
//  PreviewViewController.swift
//  AssetCatalogQuickLook
//
//  QuickLook preview for .car files
//

import Cocoa
import Quartz
import AssetCatalogKit

class PreviewViewController: NSViewController, QLPreviewingController {

    // MARK: - Properties

    private var reader: AssetCatalogReader?
    private var assets: [[String: Any]] = []

    private lazy var scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        return scroll
    }()

    private lazy var gridView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var summaryLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    // MARK: - Lifecycle

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(summaryLabel)

        scrollView.documentView = gridView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -8),

            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            summaryLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            summaryLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        reader = AssetCatalogReader(fileURL: url)

        reader?.resourceConstrainedRead(withMaxCount: 50) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else {
                    handler(nil)
                    return
                }

                if let error = self.reader?.error {
                    handler(error)
                    return
                }

                self.assets = self.reader?.assets ?? []
                self.renderPreview()
                self.updateSummary()
                handler(nil)
            }
        }
    }

    // MARK: - Rendering

    private func renderPreview() {
        // Remove existing subviews
        gridView.subviews.forEach { $0.removeFromSuperview() }

        let itemSize: CGFloat = 72
        let margin: CGFloat = 12
        let spacing: CGFloat = 8
        let viewWidth = max(view.bounds.width - margin * 2, 300)
        let columns = max(1, Int(viewWidth / (itemSize + spacing)))

        var x: CGFloat = margin
        var y: CGFloat = margin
        var maxY: CGFloat = 0

        for (index, asset) in assets.enumerated() {
            guard let imageRep = asset["imagerep"] as? NSImageRep,
                  let name = asset["name"] as? String else { continue }

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

        // Checkerboard background
        let bgView = NSView(frame: NSRect(x: 2, y: 20, width: size - 4, height: size - 4))
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        bgView.layer?.cornerRadius = 4
        container.addSubview(bgView)

        // Image
        let imageView = NSImageView(frame: NSRect(x: 4, y: 22, width: size - 8, height: size - 8))
        let image = NSImage(size: imageRep.size)
        image.addRepresentation(imageRep)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(imageView)

        // Label
        let label = NSTextField(labelWithString: name)
        label.frame = NSRect(x: 0, y: 0, width: size, height: 14)
        label.font = .systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        container.addSubview(label)

        return container
    }

    private func updateSummary() {
        let total = reader?.totalNumberOfAssets ?? 0
        let shown = assets.count
        if total > shown {
            summaryLabel.stringValue = "Showing \(shown) of \(total) assets"
        } else {
            summaryLabel.stringValue = "\(total) assets"
        }
    }
}
