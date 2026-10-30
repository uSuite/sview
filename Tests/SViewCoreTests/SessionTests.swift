import Foundation
import Testing
@testable import SViewCore

/// Moves "trashed" files into a private folder so tests never touch ~/.Trash.
final class FakeTrashFileManager: FileManager, @unchecked Sendable {
    let trashFolder: URL

    init(trashFolder: URL) {
        self.trashFolder = trashFolder
        super.init()
    }

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        let target = trashFolder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try moveItem(at: url, to: target)
        outResultingURL?.pointee = target as NSURL
    }
}

@MainActor
struct SessionTests {
    let temp: TempFolder
    let session: Session
    var effects: [Effect] { recorder.effects }
    let recorder = Recorder()

    final class Recorder {
        var effects: [Effect] = []
    }

    init() throws {
        temp = try TempFolder()
        let trash = try temp.folder("trash")
        try temp.file("poc/poc-a/poc-a-01.png")
        try temp.file("poc/poc-a/poc-a-02.png")
        try temp.file("poc/poc-a/poc-a-10.png")
        try temp.folder("poc/poc-b")
        try temp.file("poc/poc-c/poc-c-01.png")
        try temp.file("poc/poc-c/sub/deep-01.png")
        session = Session(
            paths: ConfigPaths(directory: temp.url.appendingPathComponent("config")),
            fileManager: FakeTrashFileManager(trashFolder: trash)
        )
        let recorder = recorder
        session.perform = { recorder.effects.append($0) }
    }

    private func folder(_ path: String) -> URL { temp.url.appendingPathComponent(path) }
    private var names: [String] { session.state.visible.map(\.name) }
    private var currentName: String? { session.state.current?.name }

    @Test func openFileSelectsIt() {
        session.open(folder("poc/poc-a/poc-a-02.png"))
        #expect(names == ["poc-a-01.png", "poc-a-02.png", "poc-a-10.png"])
        #expect(currentName == "poc-a-02.png")
    }

    @Test func openFolderDescendsToFirstWithImages() {
        session.open(folder("poc"))
        #expect(session.state.folder?.folder.lastPathComponent == "poc-a")
        #expect(currentName == "poc-a-01.png")
    }

    @Test func openMissingToasts() {
        session.open(folder("nope.png"))
        #expect(session.state.toast?.hasPrefix("not found") == true)
    }

    @Test func folderMovesStartAtTheFirstImage() {
        session.open(folder("poc/poc-a/poc-a-10.png"))
        #expect(session.state.position?.index == 3)
        session.dispatch(.folderNext)
        #expect(session.state.position?.index == 1)
        session.dispatch(.folderPrevious)
        #expect(currentName == "poc-a-01.png")
    }

    @Test func siblingParentEnter() {
        session.open(folder("poc/poc-a"))
        session.dispatch(.folderNext)
        #expect(session.state.folder?.folder.lastPathComponent == "poc-c")
        session.dispatch(.folderNext)
        #expect(session.state.toast == "last folder")
        session.dispatch(.folderEnter)
        #expect(session.state.folder?.folder.lastPathComponent == "sub")
        session.dispatch(.folderParent)
        #expect(session.state.folder?.folder.lastPathComponent == "poc-c")
        session.dispatch(.folderParent)
        #expect(session.state.folder?.folder.lastPathComponent == "poc")
        #expect(session.state.toast == "poc: no images")
        session.dispatch(.folderEnter)
        #expect(session.state.folder?.folder.lastPathComponent == "poc-a")
        session.dispatch(.folderPrevious)
        #expect(session.state.toast == "first folder")
        session.dispatch(.folderEnter)
        #expect(session.state.toast == "no sub-folder with images")
    }

    @Test func recursiveFlattens() {
        session.open(folder("poc/poc-c"))
        session.dispatch(.recursive)
        #expect(names == ["poc-c-01.png", "deep-01.png"])
    }

    @Test func cdRelative() {
        session.open(folder("poc/poc-a"))
        session.dispatch(.cd("../poc-c"))
        #expect(currentName == "poc-c-01.png")
    }

    @Test func rescanPicksUpNewFilesAndKeepsPosition() throws {
        session.open(folder("poc/poc-a/poc-a-02.png"))
        try temp.file("poc/poc-a/poc-a-03.png")
        session.dispatch(.reload)
        #expect(names.count == 4)
        #expect(currentName == "poc-a-02.png")
    }

    @Test func diskChangesKeepTheCurrentImage() throws {
        session.open(folder("poc/poc-a/poc-a-02.png"))
        try temp.file("poc/poc-a/poc-a-01b.png")
        try temp.file("poc/poc-a/poc-a-11.png")
        #expect(session.folderChangedOnDisk().isEmpty)
        #expect(names == ["poc-a-01.png", "poc-a-01b.png", "poc-a-02.png", "poc-a-10.png", "poc-a-11.png"])
        #expect(currentName == "poc-a-02.png")
        #expect(session.state.position?.index == 3)
        #expect(session.state.toast == "2 new images")

        try temp.file("poc/poc-a/poc-a-02.png", bytes: 99)
        try FileManager.default.removeItem(at: folder("poc/poc-a/poc-a-01b.png"))
        let changed = session.folderChangedOnDisk()
        #expect(changed.map(\.lastPathComponent) == ["poc-a-02.png"])
        #expect(names.count == 4)
        #expect(currentName == "poc-a-02.png")

        try FileManager.default.removeItem(at: folder("poc/poc-a/poc-a-02.png"))
        session.folderChangedOnDisk()
        #expect(currentName == "poc-a-10.png")
    }

    @Test func folderDeletedWhileViewing() throws {
        session.open(folder("poc/poc-c"))
        try FileManager.default.removeItem(at: folder("poc/poc-c"))
        #expect(session.folderChangedOnDisk().isEmpty)
        #expect(session.state.toast == "poc-c is gone")
        #expect(currentName == "poc-c-01.png")
    }

    @Test func noFolderNoChanges() {
        #expect(session.folderChangedOnDisk().isEmpty)
    }

    @Test func trashAndUndo() {
        session.open(folder("poc/poc-a/poc-a-02.png"))
        session.dispatch(.trash)
        #expect(names == ["poc-a-01.png", "poc-a-10.png"])
        #expect(currentName == "poc-a-10.png")
        #expect(session.state.toast == "trashed poc-a-02.png")
        session.dispatch(.undo)
        #expect(names.count == 3)
        #expect(currentName == "poc-a-02.png")
        #expect(session.state.toast == "restored poc-a-02.png")
        session.dispatch(.undo)
        #expect(session.state.toast == "nothing to undo")
    }

    @Test func trashMarked() {
        session.open(folder("poc/poc-a"))
        session.dispatch(.mark)
        session.dispatch(.last)
        session.dispatch(.mark)
        session.dispatch(.trashMarked)
        #expect(names == ["poc-a-02.png"])
        #expect(session.state.marks.isEmpty)
        #expect(session.state.toast == "trashed 2")
    }

    @Test func renameKeepsExtensionAndPosition() {
        session.open(folder("poc/poc-a/poc-a-02.png"))
        session.dispatch(.mark)
        session.dispatch(.rename("poc-a-05"))
        #expect(names == ["poc-a-01.png", "poc-a-05.png", "poc-a-10.png"])
        #expect(currentName == "poc-a-05.png")
        #expect(session.state.marks.contains(folder("poc/poc-a/poc-a-05.png")))
        session.dispatch(.rename("poc-a-01.png"))
        #expect(session.state.toast == "poc-a-01.png exists")
        session.dispatch(.rename("a/b"))
        #expect(session.state.toast == "invalid name")
    }

    @Test func setPersistsAndMapAppends() throws {
        session.dispatch(.set(key: "wrap", value: "true"))
        let config = try String(contentsOf: session.paths.config, encoding: .utf8)
        #expect(config.contains("wrap true"))
        session.dispatch(.map(keys: "gx", command: "reveal"))
        session.dispatch(.map(keys: "gy", command: "copy-name"))
        let keymap = try String(contentsOf: session.paths.keymap, encoding: .utf8)
        #expect(keymap == "gx reveal\ngy copy-name\n")
    }

    @Test func uiEffectsAreForwarded() {
        session.open(folder("poc/poc-a"))
        session.dispatch(.copyName)
        session.dispatch(.fullscreen)
        #expect(effects == [.copyText("poc-a-01.png"), .toggleFullscreen])
    }

    @Test func slideshowTickWraps() {
        session.open(folder("poc/poc-a"))
        session.slideshowTick()
        #expect(currentName == "poc-a-01.png")
        session.dispatch(.slideshow)
        session.slideshowTick()
        session.slideshowTick()
        session.slideshowTick()
        #expect(currentName == "poc-a-01.png")
        #expect(session.state.slideshow)
    }

    @Test func layoutFeedbackAndSelection() {
        session.open(folder("poc/poc-a"))
        session.updateLayout(
            effectiveScale: 0.25,
            overflowsHorizontally: true,
            overflowsVertically: false
        )
        #expect(session.state.view.effectiveScale == 0.25)
        session.dispatch(.left)
        #expect(effects == [.pan(dx: -1, dy: 0)])
        session.setZoom(.scale(500))
        #expect(session.state.view.zoom == .scale(64))
        session.setZoom(.actual)
        #expect(session.state.view.zoom == .actual)
        session.select(2)
        #expect(currentName == "poc-a-10.png")
        session.clearToast()
        #expect(session.state.toast == nil)
        var config = Config()
        config.recursive = true
        session.applyConfig(config)
        #expect(session.state.config.recursive)
    }
}
