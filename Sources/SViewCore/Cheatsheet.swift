import Foundation

/// The key cheat sheet for the README (Phase 6), generated from the shipped
/// keymap so documentation never drifts from the bindings. A comment line
/// after a blank line starts a section; other comments become notes.
public enum Cheatsheet {
    public static func markdown(keymapText: String = Keymap.defaultText) -> String {
        var out = [
            "# sView keys",
            "",
            "Generated from the built-in keymap by `make cheatsheet`; do not edit by hand. Lines in `~/.config/sview/keymap` apply on top of these, and `<keys> nop` removes one. A number before a key repeats it: `5n`, `20G`.",
        ]
        var inTable = false
        var previousBlank = false
        var seenBinding = false
        for raw in keymapText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                previousBlank = true
                continue
            }
            defer { previousBlank = false }
            if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" || $0 == " " }
                guard seenBinding || previousBlank, !text.isEmpty else {
                    continue
                }
                if previousBlank {
                    out += ["", "## " + text.prefix(1).uppercased() + text.dropFirst(), ""]
                    inTable = false
                } else {
                    out += ["", "Note: " + text, ""]
                    inTable = false
                }
                continue
            }
            guard let entry = KeyValueParser.parse(line).first,
                let keys = try? Key.parseSequence(entry.key)
            else {
                continue
            }
            seenBinding = true
            if !inTable {
                out += ["| Keys | Command |", "| --- | --- |"]
                inTable = true
            }
            let shown = keys.map(\.description).joined()
                .replacingOccurrences(of: "|", with: "\\|")
            out.append("| `\(shown)` | \(entry.value) |")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
