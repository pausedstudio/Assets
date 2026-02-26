//
//  AssetEditView.swift
//  Assets
//
//  View for editing an asset (replacing image or color)
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AssetEditView: View {
    let asset: Asset
    let onSave: (EditAction) -> Void
    let onCancel: () -> Void

    @State private var selectedImage: NSImage?
    @State private var selectedColor: Color
    @State private var showingImagePicker = false
    @State private var errorMessage: String?

    enum EditAction {
        case replaceImage(CGImage)
        case replaceColor(CGColor)
        case delete
    }

    init(asset: Asset, onSave: @escaping (EditAction) -> Void, onCancel: @escaping () -> Void) {
        self.asset = asset
        self.onSave = onSave
        self.onCancel = onCancel
        // Initialize color from asset if it's a color type
        self._selectedColor = State(initialValue: .blue)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Edit \(asset.name)")
                .font(.headline)

            Divider()

            // Content based on asset type
            if asset.assetType == .color {
                colorEditor
            } else {
                imageEditor
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Delete", role: .destructive) {
                    onSave(.delete)
                }

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.return)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 400, height: asset.assetType == .color ? 250 : 350)
    }

    // MARK: - Image Editor

    @ViewBuilder
    private var imageEditor: some View {
        VStack(spacing: 16) {
            // Current vs New comparison
            HStack(spacing: 20) {
                VStack {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(nsImage: asset.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack {
                    Text("New")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let newImage = selectedImage {
                        Image(nsImage: newImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                            .overlay {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            }

            Button("Choose Image...") {
                chooseImage()
            }

            Text("Select a PNG or JPEG image to replace the current asset")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Color Editor

    @ViewBuilder
    private var colorEditor: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(Color(nsColor: NSColor(cgColor: extractColorFromAsset()) ?? .gray))
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        }
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack {
                    Text("New")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ColorPicker("", selection: $selectedColor)
                        .labelsHidden()
                        .frame(width: 80, height: 80)
                }
            }

            Text("Choose a new color for this asset")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        if asset.assetType == .color {
            return true
        } else {
            return selectedImage != nil
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.message = "Choose an image to replace \(asset.name)"

        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                selectedImage = image
                errorMessage = nil
            } else {
                errorMessage = "Failed to load image"
            }
        }
    }

    private func saveChanges() {
        if asset.assetType == .color {
            let nsColor = NSColor(selectedColor)
            let cgColor = nsColor.cgColor
            onSave(.replaceColor(cgColor))
        } else if let nsImage = selectedImage {
            // Convert NSImage to CGImage
            var rect = NSRect(origin: .zero, size: nsImage.size)
            if let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                onSave(.replaceImage(cgImage))
            } else {
                errorMessage = "Failed to convert image"
            }
        }
    }

    private func extractColorFromAsset() -> CGColor {
        // Try to extract color from asset data if it's a color asset
        // For now, return a default
        return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    }
}

// MARK: - Edit Button for Preview

struct EditAssetButton: View {
    let asset: Asset
    let viewModel: CatalogViewModel
    @State private var showingEditSheet = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Button {
            showingEditSheet = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .disabled(!asset.isEditable)
        .sheet(isPresented: $showingEditSheet) {
            AssetEditView(
                asset: asset,
                onSave: { action in
                    handleEdit(action)
                    showingEditSheet = false
                },
                onCancel: {
                    showingEditSheet = false
                }
            )
        }
        .alert("Edit Result", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    private func handleEdit(_ action: AssetEditView.EditAction) {
        Task {
            do {
                switch action {
                case .replaceImage(let cgImage):
                    try await viewModel.replaceImage(for: asset, with: cgImage)
                    alertMessage = "Image replaced successfully"
                case .replaceColor(let cgColor):
                    try await viewModel.replaceColor(for: asset, with: cgColor)
                    alertMessage = "Color replaced successfully"
                case .delete:
                    try await viewModel.deleteAsset(asset)
                    alertMessage = "Asset deleted successfully"
                }
                showingAlert = true
            } catch {
                alertMessage = "Error: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// MARK: - Asset Extension

extension Asset {
    var isEditable: Bool {
        switch assetType {
        case .image, .imageSet, .icon, .color:
            return true
        case .vector, .data, .unknown:
            return false
        }
    }
}
