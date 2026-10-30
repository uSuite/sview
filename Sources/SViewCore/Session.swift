import Foundation
import Observation

/// One window's viewer: owns `ViewerState`, runs the dispatcher, performs
/// the file-system effects and hands the rest to the UI through `perform`.
@MainActor
@Observable
public final class Session {
    public private(set) var state: ViewerState
    public let paths: ConfigPaths
    /// Receives every effect that is not a session effect.
    @ObservationIgnored public var perform: (Effect) -> Void = { _ in }

    /// The folder under the sidebar cursor, set by the UI; `o` enters it
    /// while the sidebar shows (SV-303).
    @ObservationIgnored public var sidebarSelection: URL?

    /// Trashed files, newest last, for `u` (SV-307).
    @ObservationIgnored private var trashed: [(original: URL, inTrash: URL)] = []
    @ObservationIgnored private let fileManager: FileManager

    public init(
        config: Config = Config(),
        paths: ConfigPaths = ConfigPaths(),
        fileManager: FileManager = .default
    ) {
        state = ViewerState(config: config)
        self.paths = paths
        self.fileManager = fileManager
    }

    public func dispatch(
        _ command: Command,
        count: Int? = nil
    ) {
        dispatch(Invocation(command, count: count))
    }

    public func dispatch(_ invocation: Invocation) {
        let effects = Dispatcher.apply(invocation, to: &state)
        for effect in effects {
            if effect.isSessionEffect {
                run(effect)
            } else {
                perform(effect)
            }
        }
    }

    /// Opens a file (its folder, selecting it) or a folder (its first image,
    /// or the first descendant folder with images).
    public func open(_ input: URL) {
        // Standardize once, while the file exists; every URL derived from it
        // then shares the same form.
        let url = input.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            state.toast = "not found: \(url.path)"
            return
        }
        if isDirectory.boolValue {
            var target = url
            if !state.config.recursive, let found = try? FolderTree.firstFolderWithImages(under: url) {
                target = found
            }
            load(target, selecting: nil)
        } else {
            load(url.deletingLastPathComponent(), selecting: url)
        }
    }

    /// Slideshow advance: moves on without the stop-on-navigation rule.
    public func slideshowTick() {
        guard state.slideshow, let index = state.navigator.index else {
            return
        }
        state.select((index + 1) % state.visible.count)
    }

    /// Canvas feedback: the scale it shows and whether the image overflows.
    public func updateLayout(
        effectiveScale: Double,
        overflowsHorizontally: Bool,
        overflowsVertically: Bool
    ) {
        if state.view.effectiveScale != effectiveScale {
            state.view.effectiveScale = effectiveScale
        }
        if state.overflowsHorizontally != overflowsHorizontally {
            state.overflowsHorizontally = overflowsHorizontally
        }
        if state.overflowsVertically != overflowsVertically {
            state.overflowsVertically = overflowsVertically
        }
    }

    /// Rescans after the folder changed on disk (SV-208). New files take
    /// their sorted place, deleted ones vanish and the current image stays
    /// where it is. Returns the files whose size or date changed, so their
    /// cached decodes can be dropped.
    @discardableResult
    public func folderChangedOnDisk() -> [URL] {
        guard let model = state.folder else {
            return []
        }
        let before = Dictionary(
            model.items.map { ($0.url.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let fresh: FolderModel
        do {
            fresh = try FolderModel.load(
                model.folder,
                order: state.config.sort,
                recursive: state.config.recursive
            )
        } catch {
            state.toast = "\(model.folder.lastPathComponent) is gone"
            return []
        }
        let added = fresh.count - model.count
        state.setFolder(fresh, selecting: state.current?.url)
        if added > 0 {
            state.toast = added == 1 ? "1 new image" : "\(added) new images"
        }
        return fresh.items.compactMap { item in
            guard let old = before[item.url.path], old.size != item.size || old.modified != item.modified else {
                return nil
            }
            return item.url
        }
    }

    /// Zoom set by a gesture on the canvas (pinch, cmd-scroll, double-click).
    public func setZoom(_ zoom: ViewState.Zoom) {
        if case .scale(let scale) = zoom {
            let range = ViewState.scaleRange
            state.view.zoom = .scale(min(max(scale, range.lowerBound), range.upperBound))
        } else {
            state.view.zoom = zoom
        }
    }

    public func select(_ index: Int) {
        state.select(index)
    }

    public func clearToast() {
        state.toast = nil
    }

    public func applyConfig(_ config: Config) {
        let recursiveChanged = config.recursive != state.config.recursive
        state.setConfig(config)
        if recursiveChanged {
            run(.rescan)
        }
    }

    // MARK: Effects

    func run(_ effect: Effect) {
        switch effect {
        case .openFolder(let url, let selecting):
            if let selecting {
                load(url, selecting: selecting)
            } else {
                open(url)
            }
        case .siblingFolder(let offset):
            guard let folder = state.folder?.folder else {
                return
            }
            if let sibling = try? FolderTree.sibling(
                of: folder,
                offset: offset,
                skipEmpty: state.config.skipEmptyFolders
            ) {
                load(sibling, selecting: nil)
            } else {
                state.toast = offset > 0 ? "last folder" : "first folder"
            }
        case .parentFolder:
            guard let folder = state.folder?.folder, let parent = FolderTree.parent(of: folder) else {
                return
            }
            load(parent, selecting: nil)
            if state.visible.isEmpty {
                state.toast = parent.lastPathComponent + ": no images"
            }
        case .enterFolder:
            if state.sidebar, let selected = sidebarSelection {
                open(selected)
                return
            }
            guard let folder = state.folder?.folder,
                let child = (try? FolderScanner.subfolders(of: folder))?.first(where: FolderTree.hasImages)
            else {
                state.toast = "no sub-folder with images"
                return
            }
            load(child, selecting: nil)
        case .rescan:
            guard let folder = state.folder?.folder else {
                return
            }
            load(folder, selecting: state.current?.url)
        case .trash(let urls):
            trash(urls)
        case .undoTrash:
            undoTrash()
        case .rename(let url, let name):
            rename(url, to: name)
        case .persistSetting(let key, let value):
            do {
                try paths.persist(key, value)
            } catch {
                state.toast = "could not save \(key): \(error)"
            }
        case .appendKeymap(let line):
            appendKeymap(line)
        default:
            perform(effect)
        }
    }

    private func load(
        _ folder: URL,
        selecting url: URL?
    ) {
        do {
            let model = try FolderModel.load(
                folder,
                order: state.config.sort,
                recursive: state.config.recursive
            )
            state.setFolder(model, selecting: url)
            state.toast = nil
        } catch {
            state.toast = "cannot read \(folder.lastPathComponent)"
        }
    }

    private func trash(_ urls: [URL]) {
        var count = 0
        for url in urls {
            var result: NSURL?
            do {
                try fileManager.trashItem(at: url, resultingItemURL: &result)
                if let inTrash = result as URL? {
                    trashed.append((url, inTrash))
                }
                state.marks.unmark(url)
                count += 1
            } catch {
                state.toast = "cannot trash \(url.lastPathComponent)"
            }
        }
        if count > 0 {
            run(.rescan)
            state.toast = count == 1 ? "trashed \(urls[0].lastPathComponent)" : "trashed \(count)"
        }
    }

    private func undoTrash() {
        guard let last = trashed.popLast() else {
            state.toast = "nothing to undo"
            return
        }
        do {
            try fileManager.moveItem(at: last.inTrash, to: last.original)
            if let folder = state.folder?.folder,
                folder.path == last.original.deletingLastPathComponent().path
            {
                load(folder, selecting: last.original)
            }
            state.toast = "restored \(last.original.lastPathComponent)"
        } catch {
            state.toast = "cannot restore \(last.original.lastPathComponent)"
        }
    }

    private func rename(
        _ url: URL,
        to name: String
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            state.toast = "invalid name"
            return
        }
        // A name without an extension keeps the old one, so cw edits the stem.
        let newName = (trimmed as NSString).pathExtension.isEmpty && !url.pathExtension.isEmpty
            ? trimmed + "." + url.pathExtension
            : trimmed
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard target != url else {
            return
        }
        guard !fileManager.fileExists(atPath: target.path) else {
            state.toast = "\(newName) exists"
            return
        }
        do {
            try fileManager.moveItem(at: url, to: target)
            if state.marks.contains(url) {
                state.marks.unmark(url)
                state.marks.toggle(target)
            }
            load(url.deletingLastPathComponent(), selecting: target)
            state.toast = "renamed to \(newName)"
        } catch {
            state.toast = "cannot rename \(url.lastPathComponent)"
        }
    }

    private func appendKeymap(_ line: String) {
        do {
            let existing = (try? String(contentsOf: paths.keymap, encoding: .utf8)) ?? ""
            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            try fileManager.createDirectory(at: paths.directory, withIntermediateDirectories: true)
            try Data((existing + separator + line + "\n").utf8).write(to: paths.keymap, options: .atomic)
            state.toast = "mapped \(line)"
        } catch {
            state.toast = "could not save keymap"
        }
    }
}
