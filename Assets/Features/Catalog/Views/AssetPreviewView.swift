//
//  AssetPreviewView.swift
//  Assets
//
//  Full-size preview of an asset with metadata
//

import SwiftUI

struct AssetPreviewView: View {
    let asset: Asset
    let viewModel: CatalogViewModel

    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Image preview area
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        CheckerboardView(squareSize: 12)

                        Image(nsImage: asset.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                    }
                    .frame(
                        width: max(geometry.size.width, asset.image.size.width * zoomScale),
                        height: max(geometry.size.height, asset.image.size.height * zoomScale)
                    )
                }
            }

            Divider()

            // Info panel
            infoPanel
        }
        .navigationTitle(asset.name)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                zoomControls
                Divider()
                copyButton
                editButton
            }
        }
    }

    @ViewBuilder
    private var zoomControls: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = max(0.25, zoomScale - 0.25)
            }
        } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .help("Zoom out")

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 1.0
            }
        } label: {
            Text("\(Int(zoomScale * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(minWidth: 40)
        }
        .help("Reset zoom to 100%")

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = min(4.0, zoomScale + 0.25)
            }
        } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .help("Zoom in")
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            viewModel.copyAssetsToPasteboard([asset])
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .help("Copy to Clipboard")
    }

    @ViewBuilder
    private var editButton: some View {
        EditAssetButton(asset: asset, viewModel: viewModel)
            .help(asset.isEditable ? "Edit Asset" : "This asset type cannot be edited")
    }

    @ViewBuilder
    private var infoPanel: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                InfoLabel("Name")
                Text(asset.name)
                    .textSelection(.enabled)

                InfoLabel("Filename")
                Text(asset.filename)
                    .textSelection(.enabled)
            }

            GridRow {
                InfoLabel("Size")
                Text(asset.sizeString)
                    .monospacedDigit()

                InfoLabel("Scale")
                Text(asset.scaleString)
            }

            GridRow {
                InfoLabel("Type")
                HStack(spacing: 4) {
                    Image(systemName: asset.assetType.iconName)
                    Text(asset.isVector ? "Vector" : "Bitmap")
                }

                InfoLabel("File Size")
                Text(asset.fileSizeString)
            }
        }
        .font(.callout)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

// MARK: - Info Label

struct InfoLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 60, alignment: .trailing)
    }
}
