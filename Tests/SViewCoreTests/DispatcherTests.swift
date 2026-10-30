import Foundation
import Testing
@testable import SViewCore

@MainActor
struct DispatcherTests {
    private func items(_ count: Int) -> [ImageItem] {
        (1...count).map {
            ImageItem(
                url: URL(fileURLWithPath: "/f/img-\($0).png"),
                size: Int64($0),
                modified: Date(timeIntervalSince1970: Double(100 - $0)),
                typeIdentifier: "public.png"
            )
        }
    }

    private func state(_ count: Int = 10, config: Config = Config()) -> ViewerState {
        var state = ViewerState(config: config)
        state.setFolder(
            FolderModel(
                folder: URL(fileURLWithPath: "/f"),
                items: items(count)
            )
        )
        return state
    }

    @discardableResult
    private func run(
        _ command: Command,
        count: Int? = nil,
        _ state: inout ViewerState
    ) -> [Effect] {
        Dispatcher.apply(Invocation(command, count: count), to: &state)
    }

    @Test func navigationWithCounts() {
        var s = state()
        run(.next, &s)
        #expect(s.position?.index == 2)
        run(.next, count: 5, &s)
        #expect(s.position?.index == 7)
        run(.previous, count: 3, &s)
        #expect(s.position?.index == 4)
        run(.last, &s)
        #expect(s.position?.index == 10)
        run(.first, &s)
        #expect(s.position?.index == 1)
        run(.last, count: 6, &s)
        #expect(s.position?.index == 6)
        run(.first, count: 3, &s)
        #expect(s.position?.index == 3)
        run(.goTo(9), &s)
        #expect(s.current?.name == "img-9.png")
        #expect(s.position?.count == 10)
    }

    @Test func wrapFromConfig() {
        var config = Config()
        config.wrap = true
        var s = state(3, config: config)
        run(.previous, &s)
        #expect(s.position?.index == 3)
    }

    @Test func hjklPanWhenOverflowingElseNavigate() {
        var s = state()
        run(.right, &s)
        run(.down, count: 2, &s)
        #expect(s.position?.index == 4)
        run(.left, &s)
        run(.up, &s)
        #expect(s.position?.index == 2)
        s.overflowsHorizontally = true
        s.overflowsVertically = true
        #expect(run(.left, count: 3, &s) == [.pan(dx: -3, dy: 0)])
        #expect(run(.right, &s) == [.pan(dx: 1, dy: 0)])
        #expect(run(.up, &s) == [.pan(dx: 0, dy: -1)])
        #expect(run(.down, &s) == [.pan(dx: 0, dy: 1)])
        #expect(s.position?.index == 2)
    }

    @Test func zoomIsRelativeToWhatIsShown() {
        var s = state()
        s.view.effectiveScale = 0.5
        run(.zoomIn, &s)
        #expect(s.view.zoom == .scale(0.625))
        run(.zoomOut, count: 2, &s)
        #expect(s.view.zoom == .scale(0.5 / 1.25))
        run(.zoomOut, count: 100, &s)
        #expect(s.view.zoom == .scale(0.02))
        run(.zoomActual, &s)
        #expect(s.view.zoom == .actual)
        run(.zoomWidth, &s)
        #expect(s.view.zoom == .width)
        run(.zoomHeight, &s)
        #expect(s.view.zoom == .height)
        run(.zoomFit, &s)
        #expect(s.view.zoom == .fit)
    }

    @Test func rotateFlipResetOnImageChange() {
        var s = state()
        run(.rotateRight, &s)
        #expect(s.view.quarterTurns == 1)
        #expect(s.view.isRotatedSideways)
        run(.rotateLeft, count: 2, &s)
        #expect(s.view.quarterTurns == 3)
        run(.rotateRight, count: 5, &s)
        #expect(s.view.quarterTurns == 0)
        run(.flipHorizontal, &s)
        run(.flipVertical, &s)
        #expect(s.view.flippedHorizontally && s.view.flippedVertically)
        run(.zoomIn, &s)
        run(.next, &s)
        #expect(s.view == ViewState(mode: .fit))
    }

    @Test func togglesAndCycles() {
        var s = state()
        run(.info, &s)
        #expect(s.info == .compact)
        run(.info, &s)
        run(.info, &s)
        #expect(s.info == .off)
        for command in [Command.thumbnails, .sidebar, .memo, .help, .theatre] {
            run(command, &s)
        }
        #expect(s.thumbnails && s.sidebar && s.memo && s.help && s.theatre)
        run(.toggleTitle, &s)
        #expect(!s.showTitle)
        run(.cancel, &s)
        #expect(!s.help)
        #expect(run(.fullscreen, &s) == [.toggleFullscreen])
        #expect(run(.playPause, &s) == [.playPause])
        #expect(run(.frameNext, count: 2, &s) == [.frameStep(2)])
        #expect(run(.framePrevious, &s) == [.frameStep(-1)])
    }

    @Test func slideshowStopsOnNavigation() {
        var s = state()
        run(.slideshow, &s)
        #expect(s.slideshow)
        run(.info, &s)
        #expect(s.slideshow)
        run(.next, &s)
        #expect(!s.slideshow)
        run(.slideshow, &s)
        run(.slideshow, &s)
        #expect(!s.slideshow)
    }

    @Test func sortAndReverseKeepCurrent() {
        var s = state()
        run(.goTo(3), &s)
        run(.sort(SortOrder(key: .date)), &s)
        #expect(s.current?.name == "img-3.png")
        #expect(s.visible.first?.name == "img-10.png")
        #expect(s.toast == "sorted by date")
        run(.reverseSort, &s)
        #expect(s.visible.first?.name == "img-1.png")
        #expect(s.toast == "sorted by date desc")
        #expect(s.current?.name == "img-3.png")
    }

    @Test func filterKeepsOrMovesAndCancelClears() {
        var s = state(12)
        run(.goTo(11), &s)
        run(.filter("img-1"), &s)
        #expect(s.visible.map(\.name) == ["img-1.png", "img-10.png", "img-11.png", "img-12.png"])
        #expect(s.current?.name == "img-11.png")
        #expect(s.toast == "4 match")
        run(.filter("zzz"), &s)
        #expect(s.current == nil)
        #expect(s.toast == "no match for zzz")
        run(.cancel, &s)
        #expect(s.visible.count == 12)
        run(.filter("img-2"), &s)
        run(.filterClear, &s)
        #expect(s.visible.count == 12)
        #expect(s.current?.name == "img-2.png")
        #expect(run(.filterPrompt, &s) == [.prompt(.filter, text: "")])
    }

    @Test func marksAndMarkedActions() {
        var s = state(5)
        run(.mark, &s)
        run(.goTo(4), &s)
        run(.mark, &s)
        #expect(s.toast == "2 marked")
        run(.first, &s)
        run(.markNext, &s)
        #expect(s.position?.index == 4)
        run(.markNext, &s)
        #expect(s.position?.index == 1)
        run(.markPrevious, &s)
        #expect(s.position?.index == 4)
        #expect(run(.trashMarked, &s) == [.trash([URL(fileURLWithPath: "/f/img-1.png"), URL(fileURLWithPath: "/f/img-4.png")])])
        #expect(run(.copyMarked, &s) == [.copyText("/f/img-1.png\n/f/img-4.png")])
        #expect(run(.revealMarked, &s) == [.reveal([URL(fileURLWithPath: "/f/img-1.png"), URL(fileURLWithPath: "/f/img-4.png")])])
        #expect(run(.exportMarked("m.txt"), &s) == [.exportMarked(path: "m.txt", names: ["img-1.png", "img-4.png"])])
        run(.markAll, &s)
        #expect(s.marks.count == 5)
        run(.markClear, &s)
        #expect(s.marks.isEmpty)
        #expect(run(.trashMarked, &s).isEmpty)
        #expect(run(.copyMarked, &s).isEmpty)
        #expect(run(.revealMarked, &s).isEmpty)
    }

    @Test func fileEffects() {
        var s = state(3)
        let url = URL(fileURLWithPath: "/f/img-1.png")
        #expect(run(.trash, &s) == [.trash([url])])
        #expect(run(.undo, &s) == [.undoTrash])
        #expect(run(.rename("new"), &s) == [.rename(url, to: "new")])
        #expect(run(.copyPath, &s) == [.copyText("/f/img-1.png")])
        #expect(run(.copyName, &s) == [.copyText("img-1.png")])
        #expect(run(.copyImage, &s) == [.copyImage(url)])
        #expect(run(.reveal, &s) == [.reveal([url])])
        #expect(run(.openWith, &s) == [.openWith(url)])
        #expect(run(.quickLook, &s) == [.quickLook(url)])
        #expect(run(.newWindow, &s) == [.newWindow(url)])
        #expect(run(.renamePrompt, &s) == [.prompt(.rename, text: "img-1")])
        #expect(run(.commandLine, &s) == [.prompt(.command, text: "")])
        #expect(run(.reload, &s) == [.rescan])
        #expect(run(.quit, &s) == [.quit])
        #expect(run(.exportConfig(""), &s) == [.exportConfig(path: "")])
        #expect(run(.exportConfig("~/x.zip"), &s) == [.exportConfig(path: "~/x.zip")])
        #expect(run(.runHook("bench"), &s) == [.runHook("bench")])
        #expect(run(.runShell("ls"), &s) == [.runShell("ls")])
    }

    @Test func compareTakesTwoMarkedOrMarkedAndCurrent() {
        var s = state(5)
        #expect(run(.compare, &s).isEmpty)
        #expect(s.toast == "mark two images to compare")
        run(.goTo(2), &s)
        run(.mark, &s)
        #expect(run(.compare, &s).isEmpty)
        run(.goTo(4), &s)
        #expect(run(.compare, &s) == [.compare(URL(fileURLWithPath: "/f/img-2.png"), URL(fileURLWithPath: "/f/img-4.png"))])
        run(.goTo(5), &s)
        run(.mark, &s)
        run(.first, &s)
        #expect(run(.compare, &s) == [.compare(URL(fileURLWithPath: "/f/img-2.png"), URL(fileURLWithPath: "/f/img-5.png"))])
    }

    @Test func emptyFolderCommandsAreNoOps() {
        var s = ViewerState()
        for command in [Command.trash, .rename("x"), .copyPath, .copyName, .copyImage, .reveal, .openWith, .quickLook, .renamePrompt, .mark, .repeatLast] {
            #expect(run(command, &s).isEmpty)
        }
        #expect(run(.newWindow, &s) == [.newWindow(nil)])
        run(.markNext, &s)
        #expect(s.current == nil)
    }

    @Test func folderEffects() {
        var s = state()
        #expect(run(.folderNext, count: 3, &s) == [.siblingFolder(3)])
        #expect(run(.folderPrevious, &s) == [.siblingFolder(-1)])
        #expect(run(.folderParent, &s) == [.parentFolder])
        #expect(run(.folderEnter, &s) == [.enterFolder])
        #expect(run(.recursive, &s) == [.rescan])
        #expect(s.config.recursive)
        #expect(openedPath(run(.cd("/abs/path"), &s)) == "/abs/path")
        #expect(openedPath(run(.cd("../sib"), &s)) == "/sib")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Dispatcher.resolve("~/x", from: nil).path == home + "/x")
    }

    private func openedPath(_ effects: [Effect]) -> String? {
        guard case .openFolder(let url, nil) = effects.first else {
            return nil
        }
        return url.path
    }

    @Test func setAndMap() {
        var s = state()
        #expect(run(.set(key: "wrap", value: "true"), &s) == [.persistSetting(key: "wrap", value: "true")])
        #expect(s.config.wrap)
        run(.previous, &s)
        #expect(s.position?.index == 10)
        #expect(run(.set(key: "wrap", value: "maybe"), &s).isEmpty)
        #expect(s.toast == "wrap: 'maybe' is not true or false")
        run(.set(key: "show_title", value: "false"), &s)
        #expect(!s.showTitle)
        #expect(run(.map(keys: "gx", command: "reveal"), &s) == [.appendKeymap("gx reveal")])
        #expect(run(.map(keys: "gx", command: "fly"), &s).isEmpty)
        #expect(s.toast == "unknown command 'fly'")
    }

    @Test func repeatLastChange() {
        var s = state()
        run(.rotateRight, &s)
        run(.next, &s)
        run(.repeatLast, &s)
        #expect(s.view.quarterTurns == 1)
        run(.repeatLast, count: 2, &s)
        #expect(s.view.quarterTurns == 3)
        #expect(s.lastRepeatable == Invocation(.rotateRight, count: 2))
    }
}
