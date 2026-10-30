import Foundation

/// The single control point: applies an `Invocation` to `ViewerState` and
/// returns the effects it needs. Pure, so every command is unit tested.
public enum Dispatcher {
    /// Commands `.` repeats: the ones that change something, not moves.
    static func isRepeatable(_ command: Command) -> Bool {
        switch command {
        case .mark, .trash, .trashMarked, .rotateLeft, .rotateRight, .flipHorizontal, .flipVertical,
            .zoomIn, .zoomOut, .runShell, .runHook, .copyPath, .copyName, .copyImage:
            return true
        default:
            return false
        }
    }

    public static func apply(
        _ invocation: Invocation,
        to state: inout ViewerState
    ) -> [Effect] {
        let command = invocation.command
        if command == .repeatLast {
            guard let last = state.lastRepeatable else {
                return []
            }
            return apply(
                Invocation(
                    last.command,
                    count: invocation.count ?? last.count
                ),
                to: &state
            )
        }
        if isRepeatable(command) {
            state.lastRepeatable = invocation
        }
        if state.slideshow, stopsSlideshow(command) {
            state.slideshow = false
        }
        let n = invocation.times
        let current = state.current

        switch command {
        case .next:
            state.moveNavigator { $0.move(by: n) }
        case .previous:
            state.moveNavigator { $0.move(by: -n) }
        case .first:
            state.moveNavigator {
                if let count = invocation.count {
                    $0.go(to: count)
                } else {
                    $0.first()
                }
            }
        case .last:
            state.moveNavigator {
                if let count = invocation.count {
                    $0.go(to: count)
                } else {
                    $0.last()
                }
            }
        case .goTo(let index):
            state.moveNavigator { $0.go(to: index) }
        case .left:
            if state.overflowsHorizontally {
                return [.pan(dx: -n, dy: 0)]
            }
            state.moveNavigator { $0.move(by: -n) }
        case .right:
            if state.overflowsHorizontally {
                return [.pan(dx: n, dy: 0)]
            }
            state.moveNavigator { $0.move(by: n) }
        case .up:
            if state.overflowsVertically {
                return [.pan(dx: 0, dy: -n)]
            }
            state.moveNavigator { $0.move(by: -n) }
        case .down:
            if state.overflowsVertically {
                return [.pan(dx: 0, dy: n)]
            }
            state.moveNavigator { $0.move(by: n) }

        case .zoomIn:
            zoom(&state, by: pow(ViewState.zoomStep, Double(n)))
        case .zoomOut:
            zoom(&state, by: pow(ViewState.zoomStep, -Double(n)))
        case .zoomFit:
            state.view.zoom = .fit
        case .zoomWidth:
            state.view.zoom = .width
        case .zoomHeight:
            state.view.zoom = .height
        case .zoomActual:
            state.view.zoom = .actual
        case .rotateLeft:
            state.view.quarterTurns = ((state.view.quarterTurns - n) % 4 + 4) % 4
        case .rotateRight:
            state.view.quarterTurns = (state.view.quarterTurns + n) % 4
        case .flipHorizontal:
            state.view.flippedHorizontally.toggle()
        case .flipVertical:
            state.view.flippedVertically.toggle()
        case .fullscreen:
            return [.toggleFullscreen]
        case .theatre:
            state.theatre.toggle()
        case .toggleTitle:
            state.showTitle.toggle()
        case .info:
            state.info = state.info.next
        case .thumbnails:
            state.thumbnails.toggle()
        case .sidebar:
            state.sidebar.toggle()
        case .memo:
            state.memo.toggle()
        case .help:
            state.help.toggle()
        case .reload:
            return [.rescan]
        case .slideshow:
            state.slideshow.toggle()
            toast(&state, state.slideshow ? "slideshow" : "slideshow stopped")
        case .playPause:
            return [.playPause]
        case .frameNext:
            return [.frameStep(n)]
        case .framePrevious:
            return [.frameStep(-n)]

        case .folderNext:
            return [.siblingFolder(n)]
        case .folderPrevious:
            return [.siblingFolder(-n)]
        case .folderParent:
            return [.parentFolder]
        case .folderEnter:
            return [.enterFolder]
        case .recursive:
            state.config.recursive.toggle()
            toast(&state, state.config.recursive ? "recursive" : "single folder")
            return [.rescan]
        case .sort(let order):
            var config = state.config
            config.sort = order
            state.setConfig(config)
            toast(&state, "sorted by \(order.key.rawValue)\(order.descending ? " desc" : "")")
        case .reverseSort:
            var config = state.config
            config.sort.descending.toggle()
            state.setConfig(config)
            toast(&state, "sorted by \(config.sort.key.rawValue)\(config.sort.descending ? " desc" : "")")
        case .cd(let path):
            return [.openFolder(resolve(path, from: state.folder?.folder), selecting: nil)]

        case .filter(let pattern):
            state.setFilter(Filter(pattern))
            toast(&state, state.visible.isEmpty ? "no match for \(pattern)" : "\(state.visible.count) match")
        case .filterClear:
            state.setFilter(Filter(""))
        case .cancel:
            if !state.filter.isEmpty {
                state.setFilter(Filter(""))
            } else {
                state.help = false
            }
        case .mark:
            guard let item = current else {
                return []
            }
            for _ in 0..<n {
                state.marks.toggle(item.url)
            }
            toast(&state, "\(state.marks.count) marked")
        case .markAll:
            state.marks.mark(state.visible.map(\.url))
            toast(&state, "\(state.marks.count) marked")
        case .markClear:
            state.marks.clear()
            toast(&state, "marks cleared")
        case .markNext, .markPrevious:
            let step = command == .markNext ? 1 : -1
            for _ in 0..<n {
                guard let index = state.navigator.index,
                    let next = state.marks.nextIndex(from: index, offset: step, in: state.visible)
                else {
                    break
                }
                state.select(next)
            }

        case .trash:
            return current.map { [.trash([$0.url])] } ?? []
        case .trashMarked:
            let urls = state.marks.ordered(in: state.visible).map(\.url)
            return urls.isEmpty ? [] : [.trash(urls)]
        case .undo:
            return [.undoTrash]
        case .rename(let name):
            return current.map { [.rename($0.url, to: name)] } ?? []
        case .copyPath:
            guard let item = current else {
                return []
            }
            toast(&state, "copied path")
            return [.copyText(item.url.path)]
        case .copyName:
            guard let item = current else {
                return []
            }
            toast(&state, "copied name")
            return [.copyText(item.name)]
        case .copyImage:
            guard let item = current else {
                return []
            }
            toast(&state, "copied image")
            return [.copyImage(item.url)]
        case .copyMarked:
            let paths = state.marks.ordered(in: state.visible).map(\.url.path)
            toast(&state, "copied \(paths.count) paths")
            return paths.isEmpty ? [] : [.copyText(paths.joined(separator: "\n"))]
        case .exportMarked(let path):
            let names = state.marks.ordered(in: state.visible).map(\.name)
            return [.exportMarked(path: path, names: names)]
        case .reveal:
            return current.map { [.reveal([$0.url])] } ?? []
        case .revealMarked:
            let urls = state.marks.ordered(in: state.visible).map(\.url)
            return urls.isEmpty ? [] : [.reveal(urls)]
        case .openWith:
            return current.map { [.openWith($0.url)] } ?? []
        case .quickLook:
            return current.map { [.quickLook($0.url)] } ?? []
        case .newWindow:
            return [.newWindow(current?.url)]
        case .compare:
            // The first two marked images, or the marked one and the current.
            let marked = state.marks.ordered(in: state.visible).map(\.url)
            if marked.count >= 2 {
                return [.compare(marked[0], marked[1])]
            }
            if let one = marked.first, let item = current, item.url.path != one.path {
                return [.compare(one, item.url)]
            }
            toast(&state, "mark two images to compare")

        case .commandLine:
            return [.prompt(.command, text: "")]
        case .filterPrompt:
            return [.prompt(.filter, text: state.filter.pattern)]
        case .renamePrompt:
            return current.map { [.prompt(.rename, text: $0.stem)] } ?? []

        case .set(let key, let value):
            var config = state.config
            do {
                try config.set(key, value)
            } catch {
                toast(&state, error.description)
                return []
            }
            state.setConfig(config)
            if key == "show_title" {
                state.showTitle = config.showTitle
            }
            toast(&state, "\(key) \(value)")
            return [.persistSetting(key: key, value: value)]
        case .map(let keys, let text):
            do {
                _ = try Command.parse(text)
            } catch {
                toast(&state, error.description)
                return []
            }
            return [.appendKeymap("\(keys) \(text)")]
        case .exportConfig(let path):
            return [.exportConfig(path: path)]
        case .runHook(let name):
            return [.runHook(name)]
        case .runShell(let line):
            return [.runShell(line)]
        case .repeatLast, .nop:
            return []
        case .quit:
            return [.quit]
        }
        return []
    }

    private static func zoom(_ state: inout ViewerState, by factor: Double) {
        let base: Double
        if case .scale(let scale) = state.view.zoom {
            base = scale
        } else {
            base = state.view.effectiveScale
        }
        let range = ViewState.scaleRange
        state.view.zoom = .scale(min(max(base * factor, range.lowerBound), range.upperBound))
    }

    private static func toast(_ state: inout ViewerState, _ message: String) {
        state.toast = message
    }

    /// Navigation and prompt keys stop a running slideshow (SV-403).
    private static func stopsSlideshow(_ command: Command) -> Bool {
        switch command {
        case .slideshow, .zoomIn, .zoomOut, .info, .toggleTitle, .fullscreen:
            return false
        default:
            return true
        }
    }

    /// `:cd` paths: absolute, `~`-relative, or relative to the current folder.
    static func resolve(_ path: String, from folder: URL?) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        let base = folder ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return base.appendingPathComponent(expanded, isDirectory: true).standardizedFileURL
    }
}
