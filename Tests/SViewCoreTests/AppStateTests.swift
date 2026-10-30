import Foundation
import Testing
@testable import SViewCore

struct AppStateTests {
    @Test func recentFoldersMoveToFrontAndCap() {
        var state = AppState()
        state.noteViewed(URL(fileURLWithPath: "/a/1.png"))
        state.noteViewed(URL(fileURLWithPath: "/b/1.png"))
        state.noteViewed(URL(fileURLWithPath: "/a/2.png"))
        #expect(state.recentFolders == ["/a", "/b"])
        #expect(state.lastFile == "/a/2.png")
        for n in 0..<30 {
            state.noteViewed(URL(fileURLWithPath: "/f\(n)/x.png"))
        }
        #expect(state.recentFolders.count == AppState.recentLimit)
        #expect(state.recentFolders.first == "/f29")
        state.clearRecents()
        #expect(state.recentFolders.isEmpty)
        #expect(state.lastFile == "/f29/x.png")
    }

    @Test func roundTripsAndToleratesBadFiles() throws {
        let temp = try TempFolder()
        let file = temp.url.appendingPathComponent("sview/state.json")
        #expect(AppState.load(from: file) == AppState())
        var state = AppState()
        state.noteViewed(temp.url.appendingPathComponent("x.png"))
        try state.save(to: file)
        let loaded = AppState.load(from: file)
        #expect(loaded == state)
        #expect(loaded.existingRecentFolders.map(\.path) == [temp.url.path])
        try Data("{not json".utf8).write(to: file)
        #expect(AppState.load(from: file) == AppState())
    }
}
