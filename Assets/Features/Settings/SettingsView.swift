//
//  SettingsView.swift
//  Assets
//
//  App settings/preferences
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 128
    @AppStorage("showFilenames") private var showFilenames: Bool = true

    var body: some View {
        Form {
            Section("Display") {
                Slider(value: $thumbnailSize, in: 64...256, step: 32) {
                    Text("Thumbnail Size")
                } minimumValueLabel: {
                    Text("64")
                } maximumValueLabel: {
                    Text("256")
                }

                Toggle("Show filenames in grid", isOn: $showFilenames)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
    }
}
