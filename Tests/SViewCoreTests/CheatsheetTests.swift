import Foundation
import Testing
@testable import SViewCore

struct CheatsheetTests {
    @Test func sectionsNotesAndEscapedKeys() {
        let text = """
            # header comment, skipped
            # also skipped

            # moving
            n next
            # a note
            | flip-horizontal

            # view
            gg first
            """
        #expect(
            Cheatsheet.markdown(keymapText: text).hasSuffix(
                """
                ## Moving

                | Keys | Command |
                | --- | --- |
                | `n` | next |

                Note: a note

                | Keys | Command |
                | --- | --- |
                | `\\|` | flip-horizontal |

                ## View

                | Keys | Command |
                | --- | --- |
                | `gg` | first |

                """
            )
        )
    }

    @Test func everyDefaultBindingIsListed() {
        let sheet = Cheatsheet.markdown()
        for binding in Keymap.default.bindings {
            #expect(sheet.contains("| \(binding.text) |"), "\(binding.text)")
        }
        #expect(!sheet.contains("\u{2014}"))
    }

    /// docs/keys.md must be what `make cheatsheet` writes now.
    @Test func committedCheatsheetIsCurrent() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repo.appendingPathComponent("docs/keys.md")
        let committed = try String(contentsOf: file, encoding: .utf8)
        #expect(committed == Cheatsheet.markdown(), "run make cheatsheet")
    }
}
