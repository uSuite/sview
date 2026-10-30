import Foundation
import Testing
@testable import SViewCore

struct CompleterTests {
    @Test func commandNamesAndAliases() {
        #expect(Completer.complete("so", folder: nil) == ["sort"])
        #expect(Completer.complete("q", folder: nil) == ["q", "ql", "quick-look", "quit"])
        #expect(Completer.complete("zoom-f", folder: nil) == ["zoom-fit"])
        #expect(Completer.complete("xyz", folder: nil).isEmpty)
        #expect(Completer.complete("", folder: nil).count == Set(Command.names + Command.aliases.keys).count)
    }

    @Test func setKeysAndValues() {
        #expect(Completer.complete("set wr", folder: nil) == ["set wrap"])
        #expect(Completer.complete("set r", folder: nil) == ["set recursive", "set restore_session"])
        #expect(Completer.complete("set s", folder: nil) == [
            "set show_title", "set size_window_to_image", "set skip_empty_folders", "set slideshow_seconds", "set sort",
        ])
        #expect(Completer.complete("set wrap ", folder: nil) == ["set wrap false", "set wrap true"])
        #expect(Completer.complete("set zoom a", folder: nil) == ["set zoom actual"])
        #expect(Completer.complete("set preload ", folder: nil).isEmpty)
        #expect(Completer.complete("set wrap true x", folder: nil).isEmpty)
    }

    @Test func sortAndMap() {
        #expect(Completer.complete("sort d", folder: nil) == ["sort date"])
        #expect(Completer.complete("sort date ", folder: nil) == ["sort date asc", "sort date desc"])
        #expect(Completer.complete("map gx rev", folder: nil) == ["map gx reveal", "map gx reveal-marked", "map gx reverse-sort"])
        #expect(Completer.complete("map gx", folder: nil).isEmpty)
        #expect(Completer.complete("run e", folder: nil, hooks: ["evidence", "ls"]) == ["run evidence"])
    }

    @Test func cdDirectories() throws {
        let temp = try TempFolder()
        try temp.folder("poc/poc-demo-vm-start")
        try temp.folder("poc/poc-demo-vm-stop")
        try temp.folder("poc/.git")
        try temp.file("poc/notes.txt")
        let poc = temp.url.appendingPathComponent("poc")
        let start = poc.appendingPathComponent("poc-demo-vm-start")
        #expect(Completer.complete("cd ../poc-demo-vm-st", folder: start) == [
            "cd ../poc-demo-vm-start/", "cd ../poc-demo-vm-stop/",
        ])
        #expect(Completer.complete("cd p", folder: temp.url) == ["cd poc/"])
        #expect(Completer.complete("cd poc/", folder: temp.url) == [
            "cd poc/poc-demo-vm-start/", "cd poc/poc-demo-vm-stop/",
        ])
        #expect(Completer.complete("cd poc/.", folder: temp.url) == ["cd poc/.git/"])
        #expect(Completer.complete("cd \(poc.path)/poc-demo-vm-sta", folder: nil) == [
            "cd \(poc.path)/poc-demo-vm-start/",
        ])
        #expect(Completer.complete("cd nowhere/", folder: temp.url).isEmpty)
    }

    @Test func commonPrefix() {
        #expect(Completer.commonPrefix(["cd ../poc-demo-vm-start/", "cd ../poc-demo-vm-stop/"]) == "cd ../poc-demo-vm-st")
        #expect(Completer.commonPrefix(["one"]) == "one")
        #expect(Completer.commonPrefix([]) == "")
    }
}
