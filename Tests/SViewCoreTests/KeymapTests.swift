import Testing
@testable import SViewCore

struct KeymapTests {
    @Test func defaultKeymapHasNoIssues() {
        let (keymap, issues) = Keymap.parse(Keymap.defaultText)
        #expect(issues.isEmpty, "\(issues)")
        #expect(keymap.bindings.count > 60)
    }

    @Test func defaultKeymapCoversTheBacklogKeys() throws {
        let keymap = Keymap.default
        let expected: [(String, Command)] = [
            ("n", .next), ("p", .previous), ("space", .next), ("shift-space", .previous),
            ("gg", .first), ("G", .last), ("+", .zoomIn), ("-", .zoomOut), ("=", .zoomFit),
            ("e", .zoomActual), ("lt", .rotateLeft), ("gt", .rotateRight), ("f", .fullscreen),
            ("q", .quit), ("r", .reload), ("i", .info), ("t", .thumbnails), ("?", .help),
            ("]", .folderNext), ("[", .folderPrevious), ("o", .folderEnter), (":", .commandLine),
            ("/", .filterPrompt), ("m", .mark), ("M", .markAll), ("'", .markNext),
            ("yy", .copyPath), ("yi", .copyImage), ("yn", .copyName), ("R", .reveal),
            ("O", .openWith), ("dd", .trash), ("u", .undo), ("cw", .renamePrompt),
            ("enter", .slideshow), ("I", .memo), (".", .repeatLast), ("esc", .cancel),
        ]
        for (keys, command) in expected {
            #expect(keymap.command(for: try Key.parseSequence(keys)) == command, "\(keys)")
        }
        #expect(keymap.keys(for: .folderParent).count == 2)
    }

    @Test func userFileOverlaysTheDefaults() {
        let (keymap, issues) = Keymap.overlaid("n last\nC nop\ngx reveal\nbogus line\n")
        #expect(issues.count == 1)
        #expect(keymap.command(for: [Key("n")]) == .last)
        #expect(keymap.command(for: [Key("C")]) == nil)
        #expect(keymap.command(for: [Key("g"), Key("x")]) == .reveal)
        #expect(keymap.command(for: [Key("p")]) == .previous)
        // An old copy of the defaults still gets keys added later.
        #expect(Keymap.overlaid("n next\n").keymap.command(for: [Key("C")]) == .compare)
    }

    @Test func laterLineWinsAndIssuesAreReported() {
        let text = """
            n next
            n previous
            <nope> next
            x fly
            z next 3
            """
        let (keymap, issues) = Keymap.parse(text)
        #expect(keymap.bindings.count == 1)
        #expect(keymap.command(for: [Key("n")]) == .previous)
        #expect(issues.map(\.line) == [3, 4, 5])
        #expect(issues[0].description == "line 3: bad key 'nope'")
        #expect(issues[1].message == "unknown command 'fly'")
    }
}

struct KeyMatcherTests {
    private func matcher(_ text: String = Keymap.defaultText) -> KeyMatcher {
        KeyMatcher(keymap: Keymap.parse(text).keymap)
    }

    private func feed(_ matcher: inout KeyMatcher, _ keys: String) -> [KeyMatcher.Result] {
        keys.map { matcher.feed(Key(String($0))) }
    }

    @Test func singleKey() {
        var m = matcher()
        #expect(m.feed(Key("n")) == .matched(Invocation(.next)))
        #expect(!m.isPending)
    }

    @Test func countPrefix() {
        var m = matcher()
        #expect(feed(&m, "20G").last == .matched(Invocation(.last, count: 20)))
        #expect(feed(&m, "5n").last == .matched(Invocation(.next, count: 5)))
        #expect(feed(&m, "10j") == [.pending(display: "1"), .pending(display: "10"), .matched(Invocation(.down, count: 10))])
    }

    @Test func multiKeySequences() {
        var m = matcher()
        #expect(feed(&m, "gg") == [.pending(display: "g"), .matched(Invocation(.first))])
        #expect(feed(&m, "3dd").last == .matched(Invocation(.trash, count: 3)))
        #expect(feed(&m, "yi").last == .matched(Invocation(.copyImage)))
        #expect(feed(&m, "gx") == [.pending(display: "g"), .unmatched])
        #expect(!m.isPending)
    }

    @Test func zeroAloneIsNotACount() {
        var m = matcher("0 first\nn next")
        #expect(m.feed(Key("0")) == .matched(Invocation(.first)))
        #expect(feed(&m, "10n").last == .matched(Invocation(.next, count: 10)))
        var plain = matcher("n next")
        #expect(plain.feed(Key("0")) == .unmatched)
    }

    @Test func boundDigitIsNotACountStart() {
        var m = matcher("1 first\nn next")
        #expect(m.feed(Key("1")) == .matched(Invocation(.first)))
    }

    @Test func escClearsPendingElseIsABinding() {
        var m = matcher()
        _ = feed(&m, "5g")
        #expect(m.display == "5g")
        #expect(m.feed(Key("esc")) == .pending(display: ""))
        #expect(!m.isPending)
        #expect(m.feed(Key("esc")) == .matched(Invocation(.cancel)))
    }

    @Test func ambiguousPrefixWaitsThenFlushes() {
        var m = matcher("g first\ngg last")
        #expect(m.feed(Key("g")) == .pending(display: "g"))
        #expect(m.flush() == Invocation(.first))
        #expect(!m.isPending)
        #expect(feed(&m, "gg").last == .matched(Invocation(.last)))
        #expect(m.flush() == nil)
        _ = m.feed(Key("4"))
        #expect(m.flush() == nil)
    }

    @Test func namedKeysAndModifiers() {
        var m = matcher()
        #expect(m.feed(Key(" ", modifiers: .shift)) == .matched(Invocation(.previous)))
        #expect(m.feed(Key("n", modifiers: .control)) == .matched(Invocation(.frameNext)))
        #expect(m.feed(Key("G", modifiers: .shift)) == .matched(Invocation(.last)))
        #expect(m.keymap.bindings.isEmpty == false)
    }
}
