import AppKit
import SViewCore
import SwiftUI

/// Settings > General (SV-511): every config option as a control, then the
/// config files as a whole and the problems found in them. Hooks and keys
/// stay in the text files.
struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Viewing") {
                Picker("Zoom on open", selection: model.binding("zoom", \.zoom)) {
                    Text("Fit").tag(Config.ZoomMode.fit)
                    Text("Fit width").tag(Config.ZoomMode.width)
                    Text("Fit height").tag(Config.ZoomMode.height)
                    Text("Actual size").tag(Config.ZoomMode.actual)
                }
                background
                Picker("Scroll wheel", selection: model.binding("wheel", \.wheel)) {
                    Text("Navigates").tag(Config.Wheel.navigate)
                    Text("Zooms").tag(Config.Wheel.zoom)
                }
                Toggle("Click the left or right half to go back or forward", isOn: model.binding("click_navigates", \.clickNavigates))
            }
            Section("Folders") {
                Picker("Sort by", selection: model.binding("sort", \.sort.key)) {
                    Text("Name").tag(SortKey.name)
                    Text("Date").tag(SortKey.date)
                    Text("Size").tag(SortKey.size)
                    Text("Type").tag(SortKey.type)
                }
                Toggle("Descending", isOn: model.binding("sort", \.sort.descending))
                Toggle("Next on the last image goes to the first", isOn: model.binding("wrap", \.wrap))
                Toggle("Include sub-folders as one sequence", isOn: model.binding("recursive", \.recursive))
                Toggle("Skip sibling folders without images", isOn: model.binding("skip_empty_folders", \.skipEmptyFolders))
            }
            Section("Window") {
                Toggle("Show name, position and size in the title", isOn: model.binding("show_title", \.showTitle))
                Toggle("Size the window to the image on open", isOn: model.binding("size_window_to_image", \.sizeWindowToImage))
                Toggle("Reopen the last image when launched with nothing to open", isOn: model.binding("restore_session", \.restoreSession))
                LabeledContent("Slideshow") {
                    HStack(spacing: 4) {
                        TextField(
                            "Slideshow",
                            value: model.binding("slideshow_seconds", \.slideshowSeconds),
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        Stepper(
                            "Slideshow",
                            value: model.binding("slideshow_seconds", \.slideshowSeconds),
                            in: 0.2...3600,
                            step: 1
                        )
                        .labelsHidden()
                        Text("seconds per image")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Memory") {
                LabeledContent("Decode ahead and behind") {
                    Stepper(
                        "\(model.config.preload) images",
                        value: model.binding("preload", \.preload),
                        in: 0...20
                    )
                }
                LabeledContent("Image cache") {
                    HStack(spacing: 4) {
                        TextField(
                            "Image cache",
                            value: model.binding("cache_mb", \.cacheMB),
                            format: .number.grouping(.never)
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        Stepper(
                            "Image cache",
                            value: model.binding("cache_mb", \.cacheMB),
                            in: 16...65536,
                            step: 128
                        )
                        .labelsHidden()
                        Text("MB")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("Folder") {
                    Text(AppModel.shared.paths.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Import Config…") {
                        ConfigPanels.importConfig(model)
                    }
                    Button("Export Config…") {
                        ConfigPanels.exportConfig(model)
                    }
                    Spacer()
                    Button("Open Config Folder") {
                        NSWorkspace.shared.open(AppModel.shared.paths.directory)
                    }
                }
                if !model.status.isEmpty {
                    Text(model.status)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Config files")
            } footer: {
                Text("config and keymap are plain text; hooks and keys live there, and every change here is one line of config.")
                    .foregroundStyle(.secondary)
            }
            Section("Problems in the files") {
                if model.issues.isEmpty {
                    Text("No problems")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.issues, id: \.self) { issue in
                        Text(issue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 720)
    }

    /// Auto, checker, the three greys the parser names, or a colour of
    /// one's own, written as `#rrggbb`.
    @ViewBuilder private var background: some View {
        let text = Config.text(for: model.config.background)
        let choice = text.hasPrefix("#") ? "custom" : text
        Picker(
            "Background",
            selection: Binding(
                get: { choice },
                set: { picked in
                    if picked == "custom" {
                        model.change("background") { $0.background = .color(red: 0.16, green: 0.16, blue: 0.18) }
                    } else {
                        var probe = Config()
                        try? probe.set("background", picked)
                        model.change("background") { $0.background = probe.background }
                    }
                }
            )
        ) {
            Text("Auto").tag("auto")
            Text("Checkerboard").tag("checker")
            Text("Black").tag("black")
            Text("White").tag("white")
            Text("Grey").tag("grey")
            Text("Colour").tag("custom")
        }
        if choice == "custom", case .color(let red, let green, let blue) = model.config.background {
            ColorPicker(
                "Colour",
                selection: Binding(
                    get: { Color(red: red, green: green, blue: blue) },
                    set: { color in
                        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
                            return
                        }
                        model.change("background") {
                            $0.background = .color(
                                red: srgb.redComponent,
                                green: srgb.greenComponent,
                                blue: srgb.blueComponent
                            )
                        }
                    }
                ),
                supportsOpacity: false
            )
        }
    }
}
