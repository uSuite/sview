import Foundation
import Testing
@testable import SViewCore

/// SV-511: what the Settings window writes for each control.
struct SettingsTextTests {
    private func roundTrips(_ config: Config) throws {
        for key in Config.keys {
            let text = try #require(config.text(for: key), "\(key) has no text")
            var parsed = Config()
            try parsed.set(key, text)
            #expect(parsed.text(for: key) == text, "\(key) \(text)")
        }
        var rebuilt = Config()
        for key in Config.keys {
            try rebuilt.set(key, config.text(for: key)!)
        }
        #expect(rebuilt == config)
    }

    @Test func everyKeyOfTheDefaultsRoundTrips() throws {
        try roundTrips(Config())
        #expect(Config().text(for: "hook") == nil)
        #expect(Config().text(for: "sort") == "name")
        #expect(Config().text(for: "slideshow_seconds") == "3")
    }

    @Test func everyKeyOfAChangedConfigRoundTrips() throws {
        let (config, issues) = Config.parse("""
            preload 5
            cache_mb 2048
            wrap true
            sort date desc
            recursive true
            skip_empty_folders false
            background #1e2a3b
            zoom width
            wheel zoom
            click_navigates true
            slideshow_seconds 1.5
            show_title false
            size_window_to_image true
            restore_session true
            """)
        #expect(issues.isEmpty)
        try roundTrips(config)
        #expect(config.text(for: "sort") == "date desc")
        #expect(config.text(for: "background") == "#1e2a3b")
        #expect(config.text(for: "slideshow_seconds") == "1.5")
    }

    @Test func namedBackgroundsKeepTheirNames() {
        for name in ["auto", "checker", "black", "white", "grey"] {
            var config = Config()
            try? config.set("background", name)
            #expect(config.text(for: "background") == name)
        }
    }

    @Test func importChecksEachFileAsTheAppDoes() {
        #expect(ConfigArchive.sview.app == "sview")
        #expect(ConfigArchive.sview.fileNames == ["config", "keymap"])
        #expect(ConfigArchive.sviewIssues(name: "config", text: "wrap maybe\n") == ["line 1: wrap: 'maybe' is not true or false"])
        #expect(ConfigArchive.sviewIssues(name: "config", text: Config.defaultText).isEmpty)
        #expect(ConfigArchive.sviewIssues(name: "keymap", text: "j bogus-command\n").count == 1)
    }
}
