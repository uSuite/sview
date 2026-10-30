import Foundation
import Testing
@testable import SViewCore

struct FolderListingTests {
    private func tree() throws -> TempFolder {
        let temp = try TempFolder()
        try temp.file("poc/poc-a/a-01.png")
        try temp.file("poc/poc-a/a-02.png")
        try temp.file("poc/poc-a/sub/s-01.png")
        try temp.folder("poc/poc-a/empty")
        try temp.file("poc/poc-b/b-01.png")
        try temp.folder("poc/poc-c")
        try temp.file("poc/cover.png")
        return temp
    }

    @Test func listsParentSiblingsAndChildrenWithCounts() async throws {
        let temp = try tree()
        let rows = await FolderListing.entries(for: temp.url.appendingPathComponent("poc/poc-a"))
        #expect(rows.map(\.name) == ["..", "poc-a", "empty", "sub", "poc-b", "poc-c"])
        #expect(rows.map(\.imageCount) == [1, 2, 0, 1, 1, 0])
        #expect(rows.map(\.kind) == [.parent, .sibling, .child, .child, .sibling, .sibling])
        #expect(rows.filter(\.isCurrent).map(\.name) == ["poc-a"])
    }

    @Test func filterKeepsParentAndCurrent() async throws {
        let temp = try tree()
        let rows = await FolderListing.entries(for: temp.url.appendingPathComponent("poc/poc-a"))
        #expect(FolderListing.filter(rows, by: "-B").map(\.name) == ["..", "poc-a", "poc-b"])
        #expect(FolderListing.filter(rows, by: "").count == rows.count)
    }

    @MainActor
    @Test func enterFolderUsesTheSidebarSelectionWhileItShows() throws {
        let temp = try tree()
        let session = Session(paths: ConfigPaths(directory: temp.url.appendingPathComponent("config")))
        session.open(temp.url.appendingPathComponent("poc/poc-a"))
        session.sidebarSelection = temp.url.appendingPathComponent("poc/poc-b")
        session.dispatch(.folderEnter)
        #expect(session.state.folder?.folder.lastPathComponent == "sub")
        session.dispatch(.sidebar)
        session.dispatch(.folderEnter)
        #expect(session.state.folder?.folder.lastPathComponent == "poc-b")
    }
}
