import Foundation
import Testing
@testable import SViewCore

struct CommandTests {
    @Test func everySimpleNameParses() throws {
        for (name, command) in Command.simple {
            #expect(try Command.parse(name) == command)
            #expect(try Command.parse("  \(name)  ") == command)
        }
    }

    @Test func argumentCommands() throws {
        #expect(try Command.parse("go-to 20") == .goTo(20))
        #expect(try Command.parse("sort date desc") == .sort(SortOrder(key: .date, descending: true)))
        #expect(try Command.parse("sort size") == .sort(SortOrder(key: .size)))
        #expect(try Command.parse("cd ~/poc") == .cd("~/poc"))
        #expect(try Command.parse("filter vm-") == .filter("vm-"))
        #expect(try Command.parse("rename case-01") == .rename("case-01"))
        #expect(try Command.parse("export-marked") == .exportMarked(""))
        #expect(try Command.parse("export-marked /tmp/x.txt") == .exportMarked("/tmp/x.txt"))
        #expect(try Command.parse("set wrap true") == .set(key: "wrap", value: "true"))
        #expect(try Command.parse("set sort date desc") == .set(key: "sort", value: "date desc"))
        #expect(try Command.parse("map gx  run-shell open $FILE") == .map(keys: "gx", command: "run-shell open $FILE"))
        #expect(try Command.parse("run bench") == .runHook("bench"))
        #expect(
            try Command.parse("run-shell python3 ../report.py --dry-run")
                == .runShell("python3 ../report.py --dry-run")
        )
    }

    @Test func errors() {
        #expect(throws: Command.ParseError.empty) { try Command.parse("   ") }
        #expect(throws: Command.ParseError.unknown("fly")) { try Command.parse("fly") }
        #expect(throws: Command.ParseError.badArgument(command: "next", reason: "takes no argument")) {
            try Command.parse("next 3")
        }
        for bad in ["go-to", "go-to 0", "go-to x", "sort", "sort shape", "cd", "filter", "rename", "set wrap", "map gx", "run", "run-shell"] {
            #expect(throws: Command.ParseError.self) { try Command.parse(bad) }
        }
        #expect(Command.ParseError.unknown("x").description == "unknown command 'x'")
        #expect(Command.ParseError.empty.description == "no command")
        #expect(Command.ParseError.badArgument(command: "a", reason: "b").description == "a: b")
    }

    @Test func commandLine() throws {
        #expect(try Command.parseCommandLine("42") == .goTo(42))
        #expect(try Command.parseCommandLine("0") == .goTo(1))
        #expect(try Command.parseCommandLine("q") == .quit)
        #expect(try Command.parseCommandLine("ql") == .quickLook)
        #expect(try Command.parseCommandLine("export") == .exportConfig(""))
        #expect(try Command.parseCommandLine("export ~/backup.zip") == .exportConfig("~/backup.zip"))
        #expect(try Command.parseCommandLine("marked /tmp/m.txt") == .exportMarked("/tmp/m.txt"))
        #expect(try Command.parseCommandLine("sort name desc") == .sort(SortOrder(key: .name, descending: true)))
        #expect(try Command.parseCommandLine(" reveal ") == .reveal)
    }

    @Test func countAcceptance() {
        #expect(Command.next.acceptsCount)
        #expect(Command.folderNext.acceptsCount)
        #expect(!Command.quit.acceptsCount)
        #expect(!Command.trash.acceptsCount)
    }
}

struct CommandTextTests {
    @Test func everyCommandRoundTrips() throws {
        var commands = Array(Command.simple.values)
        commands += [
            .goTo(7),
            .sort(SortOrder(key: .date, descending: true)),
            .sort(SortOrder(key: .size)),
            .cd("~/poc"),
            .filter("vm-"),
            .rename("case-01"),
            .exportMarked(""),
            .exportMarked("m.txt"),
            .exportConfig(""),
            .exportConfig("~/s.zip"),
            .set(key: "wrap", value: "true"),
            .map(keys: "gx", command: "reveal"),
            .runHook("bench"),
            .runShell("ls -l"),
        ]
        for command in commands {
            #expect(try Command.parse(command.text) == command, "\(command.text)")
        }
    }

    @Test func namesCoverTheParser() throws {
        #expect(Command.names.count == Command.simple.count + 11)
        #expect(Command.names == Command.names.sorted())
        for name in Command.names where Command.simple[name] == nil && !name.hasPrefix("export-") {
            #expect(throws: Command.ParseError.self) { try Command.parse(name) }
        }
    }
}

struct DefaultKeymapFiringTests {
    /// Every shipped binding, fed key by key, fires exactly its command.
    @Test func everyDefaultBindingFires() {
        let keymap = Keymap.default
        for binding in keymap.bindings {
            var matcher = KeyMatcher(keymap: keymap)
            var fired: Invocation?
            for key in binding.keys {
                if case .matched(let invocation) = matcher.feed(key) {
                    fired = invocation
                }
            }
            if fired == nil {
                fired = matcher.flush()
            }
            #expect(fired == Invocation(binding.command), "\(binding.text)")
        }
    }

    /// Every shipped binding dispatches on a populated state without trapping.
    @Test func everyDefaultBindingDispatches() {
        var state = ViewerState()
        state.setFolder(
            FolderModel(
                folder: URL(fileURLWithPath: "/f"),
                items: (1...5).map {
                    ImageItem(
                        url: URL(fileURLWithPath: "/f/\($0).png"),
                        size: 1,
                        modified: .distantPast,
                        typeIdentifier: "public.png"
                    )
                }
            )
        )
        for binding in Keymap.default.bindings {
            _ = Dispatcher.apply(Invocation(binding.command, count: 3), to: &state)
        }
        #expect(state.visible.count == 5)
    }
}
