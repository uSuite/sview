import Foundation
import Testing
@testable import SViewCore

struct ConfigTests {
    @Test func defaultTextParsesToDefaults() {
        let (config, issues) = Config.parse(Config.defaultText)
        #expect(issues.isEmpty)
        #expect(config == Config())
    }

    @Test func defaultTextCoversEveryKey() {
        let keys = KeyValueParser.parse(Config.defaultText).map(\.key)
        #expect(keys.sorted() == Config.keys.sorted())
    }

    @Test func parsesValues() {
        let text = """
            preload 4
            cache_mb 1024
            wrap yes
            sort date desc
            recursive on
            skip_empty_folders 0
            background #ff8000
            zoom actual
            wheel zoom
            click_navigates true
            slideshow_seconds 1.5
            show_title false
            size_window_to_image true
            restore_session yes
            """
        let (config, issues) = Config.parse(text)
        #expect(issues.isEmpty)
        #expect(config.restoreSession)
        #expect(config.preload == 4)
        #expect(config.cacheMB == 1024)
        #expect(config.wrap)
        #expect(config.sort == SortOrder(key: .date, descending: true))
        #expect(config.recursive)
        #expect(!config.skipEmptyFolders)
        #expect(config.background == .color(red: 1, green: 128.0 / 255, blue: 0))
        #expect(config.zoom == .actual)
        #expect(config.wheel == .zoom)
        #expect(config.clickNavigates)
        #expect(config.slideshowSeconds == 1.5)
        #expect(!config.showTitle)
        #expect(config.sizeWindowToImage)
    }

    @Test func namedBackgrounds() throws {
        var config = Config()
        try config.set("background", "checker")
        #expect(config.background == .checker)
        try config.set("background", "white")
        #expect(config.background == .color(red: 1, green: 1, blue: 1))
        try config.set("background", "grey")
        #expect(config.background == .color(red: 0.5, green: 0.5, blue: 0.5))
        try config.set("background", "black")
        #expect(config.background == .color(red: 0, green: 0, blue: 0))
        try config.set("background", "auto")
        #expect(config.background == .auto)
    }

    @Test func badLinesBecomeIssuesAndKeepDefaults() {
        let text = """
            preload lots
            colour red
            sort name sideways
            sort shape
            wrap maybe
            background #12
            zoom huge
            slideshow_seconds 0
            cache_mb 1
            """
        let (config, issues) = Config.parse(text)
        #expect(config == Config())
        #expect(issues.map(\.line) == Array(1...9))
        #expect(issues[1].description == "line 2: unknown option 'colour'")
        #expect(issues[6].message.contains("fit, width, height, actual"))
    }

    @Test func hooksAreNamedCommands() throws {
        let (config, issues) = Config.parse("hook evidence python3 ../report.py --dry-run\nhook ls ls -la\nhook bad\n")
        #expect(config.hooks == ["evidence": "python3 ../report.py --dry-run", "ls": "ls -la"])
        #expect(issues.map(\.line) == [3])
    }

    @Test func sortAscendingExplicit() throws {
        var config = Config()
        try config.set("sort", "SIZE asc")
        #expect(config.sort == SortOrder(key: .size))
    }
}

struct ConfigPathsTests {
    @Test func xdgWinsOverHome() {
        let paths = ConfigPaths(
            environment: ["XDG_CONFIG_HOME": "/xdg"],
            home: URL(fileURLWithPath: "/Users/me")
        )
        #expect(paths.directory.path == "/xdg/sview")
        #expect(paths.config.path == "/xdg/sview/config")
        #expect(paths.keymap.path == "/xdg/sview/keymap")
        #expect(paths.state.path == "/xdg/sview/state.json")
    }

    @Test func relativeXdgIsIgnored() {
        let paths = ConfigPaths(
            environment: ["XDG_CONFIG_HOME": "relative"],
            home: URL(fileURLWithPath: "/Users/me")
        )
        #expect(paths.directory.path == "/Users/me/.config/sview")
    }

    @Test func ensureDefaultsWritesOnceAndPersistEditsOneLine() throws {
        let temp = try TempFolder()
        let paths = ConfigPaths(directory: temp.url.appendingPathComponent("sview"))
        #expect(paths.loadConfig().config == Config())
        try paths.ensureDefaults(keymap: "n next\n")
        #expect(try String(contentsOf: paths.keymap, encoding: .utf8) == "n next\n")
        try paths.ensureDefaults(keymap: "changed\n")
        #expect(try String(contentsOf: paths.keymap, encoding: .utf8) == "n next\n")

        try paths.persist("wrap", "true")
        let text = try String(contentsOf: paths.config, encoding: .utf8)
        #expect(text.contains("\nwrap true\n"))
        #expect(text.contains("# next on the last image goes to the first"))
        #expect(paths.loadConfig().config.wrap)
        #expect(throws: Config.SetError.self) {
            try paths.persist("wrap", "perhaps")
        }
    }
}
