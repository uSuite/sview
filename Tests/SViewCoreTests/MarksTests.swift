import Foundation
import Testing
@testable import SViewCore

struct MarksTests {
    private let items = (1...5).map {
        ImageItem(
            url: URL(fileURLWithPath: "/f/\($0).png"),
            size: 0,
            modified: .distantPast,
            typeIdentifier: "public.png"
        )
    }

    @Test func toggleMarkAllClear() {
        var marks = Marks()
        #expect(marks.isEmpty)
        let moved1 = marks.toggle(items[1].url)
        #expect(moved1)
        #expect(marks.contains(items[1].url))
        let moved2 = marks.toggle(items[1].url)
        #expect(!moved2)
        #expect(!marks.contains(items[1].url))
        marks.mark(items.map(\.url))
        #expect(marks.count == 5)
        marks.unmark(items[0].url)
        #expect(marks.count == 4)
        marks.clear()
        #expect(marks.isEmpty)
    }

    @Test func matchesWithoutTheFileExisting() {
        var marks = Marks()
        marks.toggle(URL(fileURLWithPath: "/private/var/gone/x.png"))
        #expect(marks.contains(URL(fileURLWithPath: "/private/var/gone/x.png")))
        marks.unmark(URL(fileURLWithPath: "/private/var/gone/x.png"))
        #expect(marks.isEmpty)
    }

    @Test func orderedFollowsSequence() {
        var marks = Marks()
        marks.toggle(items[4].url)
        marks.toggle(items[0].url)
        #expect(marks.ordered(in: items).map(\.name) == ["1.png", "5.png"])
    }

    @Test func nextIndexWraps() {
        var marks = Marks()
        #expect(marks.nextIndex(from: 0, in: items) == nil)
        marks.toggle(items[1].url)
        marks.toggle(items[3].url)
        #expect(marks.nextIndex(from: 0, in: items) == 1)
        #expect(marks.nextIndex(from: 1, in: items) == 3)
        #expect(marks.nextIndex(from: 3, in: items) == 1)
        #expect(marks.nextIndex(from: 2, offset: -1, in: items) == 1)
        #expect(marks.nextIndex(from: 1, offset: -1, in: items) == 3)
    }
}
