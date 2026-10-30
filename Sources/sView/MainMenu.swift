import AppKit
import SViewCore

/// Carries a `Command` on a menu item to the key window's controller.
final class CommandBox: NSObject {
    let command: Command

    init(_ command: Command) {
        self.command = command
    }
}

/// The menu bar (SV-501). Every command is listed; the vim key bound to it in
/// the live keymap is shown right-aligned in the title, and the usual Mac
/// shortcuts are key equivalents. Rebuilt when the keymap changes.
@MainActor
enum MainMenu {
    private enum Entry {
        case command(String, Command, key: String = "", modifiers: NSEvent.ModifierFlags = .command)
        case action(String, Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command)
        case submenu(String, [Entry])
        case separator
        case recents
    }

    /// Fills File > Open Recent from the saved state each time it opens.
    private final class RecentsDelegate: NSObject, NSMenuDelegate {
        func menuNeedsUpdate(_ menu: NSMenu) {
            MainActor.assumeIsolated {
                menu.removeAllItems()
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                for folder in AppModel.shared.appState.existingRecentFolders {
                    let title = folder.path.hasPrefix(home) ? "~" + folder.path.dropFirst(home.count) : folder.path
                    let item = NSMenuItem(title: title, action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
                    item.representedObject = folder
                    menu.addItem(item)
                }
                if menu.items.isEmpty {
                    let empty = NSMenuItem(title: "No Recent Folders", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                }
                menu.addItem(.separator())
                menu.addItem(withTitle: "Clear Menu", action: #selector(AppDelegate.clearRecents(_:)), keyEquivalent: "")
            }
        }
    }

    private static let recentsDelegate = RecentsDelegate()

    static func build(keymap explicit: Keymap? = nil) -> NSMenu {
        let keymap = explicit ?? AppModel.shared.keymap
        let main = NSMenu()
        let menus: [(String, [Entry])] = [
            (
                "sView",
                [
                    .action("About sView", #selector(AppDelegate.showAbout(_:))),
                    .separator,
                    .action("Settings…", #selector(AppDelegate.showSettings(_:)), key: ","),
                    .action("Open Config Folder", #selector(AppDelegate.openConfigFolder(_:))),
                    .separator,
                    .action("Hide sView", #selector(NSApplication.hide(_:)), key: "h"),
                    .action("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]),
                    .action("Show All", #selector(NSApplication.unhideAllApplications(_:))),
                    .separator,
                    .action("Quit sView", #selector(NSApplication.terminate(_:)), key: "q"),
                ]
            ),
            (
                "File",
                [
                    .action("Open…", #selector(AppDelegate.openDocument(_:)), key: "o"),
                    .recents,
                    .command("New Window", .newWindow, key: "n"),
                    .action("Close Window", #selector(NSWindow.performClose(_:)), key: "w"),
                    .separator,
                    .command("Reveal in Finder", .reveal, key: "r", modifiers: [.command, .shift]),
                    .command("Open With Default App", .openWith),
                    .command("Quick Look", .quickLook, key: "y"),
                    .command("Rename…", .renamePrompt),
                    .command("Reload Folder", .reload),
                    .separator,
                    .command("Move to Trash", .trash, key: "\u{8}"),
                    .command("Export Config to Desktop", .exportConfig("")),
                ]
            ),
            (
                "Edit",
                [
                    .command("Undo Trash", .undo, key: "z"),
                    .separator,
                    .command("Copy Image", .copyImage, key: "c"),
                    .command("Copy Path", .copyPath, key: "c", modifiers: [.command, .option]),
                    .command("Copy Name", .copyName),
                    .separator,
                    .command("Command Line…", .commandLine),
                    .command("Filter…", .filterPrompt, key: "f"),
                    .command("Clear Filter", .filterClear),
                    .command("Repeat Last Change", .repeatLast),
                ]
            ),
            (
                "View",
                [
                    .command("Zoom In", .zoomIn, key: "+"),
                    .command("Zoom Out", .zoomOut, key: "-"),
                    .command("Actual Size", .zoomActual, key: "0"),
                    .command("Fit to Window", .zoomFit, key: "9"),
                    .command("Fit Width", .zoomWidth),
                    .command("Fit Height", .zoomHeight),
                    .separator,
                    .command("Rotate Left", .rotateLeft, key: "l"),
                    .command("Rotate Right", .rotateRight, key: "r"),
                    .command("Flip Horizontal", .flipHorizontal),
                    .command("Flip Vertical", .flipVertical),
                    .separator,
                    .command("Info", .info, key: "i"),
                    .command("Thumbnails", .thumbnails),
                    .command("Sidebar", .sidebar),
                    .command("Memo", .memo),
                    .command("Window Title", .toggleTitle),
                    .command("Key Help", .help, key: "/"),
                    .separator,
                    .command("Slideshow", .slideshow),
                    .command("Play or Pause Animation", .playPause),
                    .command("Theatre", .theatre),
                    .command("Full Screen", .fullscreen, key: "f", modifiers: [.command, .control]),
                ]
            ),
            (
                "Go",
                [
                    .command("Next Image", .next),
                    .command("Previous Image", .previous),
                    .command("First Image", .first),
                    .command("Last Image", .last),
                    .separator,
                    .command("Next Folder", .folderNext, key: "]"),
                    .command("Previous Folder", .folderPrevious, key: "["),
                    .command("Parent Folder", .folderParent, key: "\u{F700}"),
                    .command("Enter Folder", .folderEnter, key: "\u{F701}"),
                    .command("Recursive", .recursive),
                    .separator,
                    .submenu(
                        "Sort By",
                        [
                            .command("Name", .sort(SortOrder(key: .name))),
                            .command("Date", .sort(SortOrder(key: .date))),
                            .command("Size", .sort(SortOrder(key: .size))),
                            .command("Type", .sort(SortOrder(key: .type))),
                            .separator,
                            .command("Reverse", .reverseSort),
                        ]
                    ),
                ]
            ),
            (
                "Marks",
                [
                    .command("Toggle Mark", .mark),
                    .command("Mark All", .markAll),
                    .command("Clear Marks", .markClear),
                    .command("Next Marked", .markNext),
                    .command("Previous Marked", .markPrevious),
                    .separator,
                    .command("Copy Marked Paths", .copyMarked),
                    .command("Reveal Marked", .revealMarked),
                    .command("Export Marked Names", .exportMarked("")),
                    .command("Compare Marked Side by Side", .compare),
                    .command("Trash Marked", .trashMarked),
                ]
            ),
            (
                "Window",
                [
                    .action("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
                    .action("Zoom", #selector(NSWindow.performZoom(_:))),
                    .separator,
                    .action("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
                ]
            ),
            ("Help", [.command("sView Key Help", .help)]),
        ]
        for (title, entries) in menus {
            let item = NSMenuItem()
            item.submenu = menu(title, entries, keymap: keymap)
            main.addItem(item)
            if title == "Window" {
                NSApp.windowsMenu = item.submenu
            } else if title == "Help" {
                NSApp.helpMenu = item.submenu
            }
        }
        return main
    }

    /// The canvas's right-click menu (SV-309): the everyday commands.
    static func contextMenu(keymap explicit: Keymap? = nil) -> NSMenu {
        let entries: [Entry] = [
            .command("Next Image", .next),
            .command("Previous Image", .previous),
            .separator,
            .command("Fit to Window", .zoomFit),
            .command("Actual Size", .zoomActual),
            .command("Rotate Left", .rotateLeft),
            .command("Rotate Right", .rotateRight),
            .separator,
            .command("Toggle Mark", .mark),
            .command("Copy Image", .copyImage),
            .command("Copy Path", .copyPath),
            .command("Reveal in Finder", .reveal),
            .command("Open With Default App", .openWith),
            .command("Quick Look", .quickLook),
            .command("Rename…", .renamePrompt),
            .command("Move to Trash", .trash),
            .separator,
            .command("Info", .info),
            .command("Thumbnails", .thumbnails),
            .command("Sidebar", .sidebar),
            .command("Memo", .memo),
        ]
        return menu("", entries.map(withoutKeyEquivalent), keymap: explicit ?? AppModel.shared.keymap)
    }

    /// Context menus show vim keys but no key equivalents.
    private static func withoutKeyEquivalent(_ entry: Entry) -> Entry {
        if case .command(let name, let command, _, _) = entry {
            return .command(name, command)
        }
        return entry
    }

    private static func menu(
        _ title: String,
        _ entries: [Entry],
        keymap: Keymap
    ) -> NSMenu {
        let menu = NSMenu(title: title)
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .recents:
                let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: "Open Recent")
                submenu.delegate = recentsDelegate
                item.submenu = submenu
                menu.addItem(item)
            case .submenu(let name, let children):
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.submenu = self.menu(name, children, keymap: keymap)
                menu.addItem(item)
            case .action(let name, let selector, let key, let modifiers):
                let item = NSMenuItem(title: name, action: selector, keyEquivalent: key)
                item.keyEquivalentModifierMask = modifiers
                menu.addItem(item)
            case .command(let name, let command, let key, let modifiers):
                let item = NSMenuItem(
                    title: name,
                    action: #selector(ViewerWindowController.performMenuCommand(_:)),
                    keyEquivalent: key
                )
                item.keyEquivalentModifierMask = modifiers
                item.representedObject = CommandBox(command)
                if let keys = keymap.keys(for: command).first {
                    item.attributedTitle = titled(name, vimKeys: keys.map(\.description).joined())
                }
                menu.addItem(item)
            }
        }
        return menu
    }

    /// `name` with the vim keys right-aligned in a dimmer colour.
    private static func titled(_ name: String, vimKeys: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ]
        )
        title.append(
            NSAttributedString(
                string: "\t" + vimKeys,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]
            )
        )
        return title
    }
}
