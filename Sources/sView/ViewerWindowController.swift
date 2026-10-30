import AppKit
import SViewCore
import SwiftUI

/// One viewer window: owns a `Session`, renders its state and performs the
/// UI effects the session hands over.
@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let session: Session
    var onClose: () -> Void = {}
    private let rootView = ViewerRootView()
    let canvas = ImageCanvasView()
    let strip = ThumbnailStripView()
    let sidebar = SidebarView()
    let memoPane = MemoPaneView()
    let helpPane = HelpPaneView()
    let outputPane = OutputPaneView()
    /// Canvas trailing edge: the window edge, or the memo pane when it shows.
    private var canvasToRight: NSLayoutConstraint?
    private var canvasToMemo: NSLayoutConstraint?
    /// Canvas leading edge: the window edge, or the sidebar when it shows.
    private var canvasToLeft: NSLayoutConstraint?
    private var canvasToSidebar: NSLayoutConstraint?
    /// Canvas bottom: the window edge, or the strip's top when it shows.
    private var canvasToWindow: NSLayoutConstraint?
    private var canvasToStrip: NSLayoutConstraint?
    let prompt = CommandPromptView()
    let overlay = OverlayModel()
    let keyboard = KeyboardState()
    let animation = AnimationPlayer()
    private let pipeline = AppModel.shared.pipeline

    /// File shown by the canvas and its header info.
    private var shownURL: URL?
    private var shownInfo: ImageInfo?
    private var loadGeneration = 0
    private var upgradeTask: Task<Void, Never>?
    private var firstFrameLogged = false
    private var folderWatcher: FSEventWatcher?
    private var watchedFolder: URL?

    init() {
        session = Session(
            config: AppModel.shared.config,
            paths: AppModel.shared.paths
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "sView"
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 320, height: 240)
        window.contentView = rootView
        window.setFrameAutosaveName("sView.viewer")
        if let size = Bench.windowSize {
            window.setContentSize(size)
            window.center()
        } else if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            window.setContentSize(NSSize(width: 1000, height: 700))
            window.center()
        }
        super.init(window: window)
        window.delegate = self
        installCanvas()
        installOverlays()
        animation.onFrame = { [weak self] image in
            guard let self, let info = self.shownInfo else {
                return
            }
            self.canvas.show(image, pixelSize: CGSize(width: info.width, height: info.height), newFile: false)
        }
        rootView.onDrop = { [weak self] urls in
            self?.open(urls[0])
        }
        session.perform = { [weak self] effect in
            self?.perform(effect)
        }
        observe()
        // Test hooks start on the first image; a window that shows none
        // (empty, or an undecodable file) starts them after half a second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.firstFrameLogged else {
                return
            }
            self.firstFrameLogged = true
            Bench.firstFrame(in: self.rootView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func installCanvas() {
        canvas.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(canvas, positioned: .below, relativeTo: nil)
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.isHidden = true
        rootView.addSubview(strip)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.isHidden = true
        rootView.addSubview(sidebar)
        memoPane.translatesAutoresizingMaskIntoConstraints = false
        memoPane.isHidden = true
        rootView.addSubview(memoPane)
        canvasToRight = canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        canvasToMemo = canvas.trailingAnchor.constraint(equalTo: memoPane.leadingAnchor)
        canvasToWindow = canvas.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        canvasToStrip = canvas.bottomAnchor.constraint(equalTo: strip.topAnchor)
        canvasToLeft = canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
        canvasToSidebar = canvas.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        NSLayoutConstraint.activate([
            canvasToLeft!,
            canvasToRight!,
            memoPane.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            memoPane.topAnchor.constraint(equalTo: rootView.topAnchor),
            memoPane.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            canvas.topAnchor.constraint(equalTo: rootView.topAnchor),
            canvasToWindow!,
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        sidebar.onOpen = { [weak self] url in
            self?.session.open(url)
        }
        sidebar.onSelectionChange = { [weak self] url in
            self?.session.sidebarSelection = url
        }
        sidebar.onDismiss = { [weak self] in
            guard let self else {
                return
            }
            self.window?.makeFirstResponder(self.canvas)
        }
        sidebar.onHide = { [weak self] in
            self?.session.dispatch(.sidebar)
        }
        strip.onSelect = { [weak self] index in
            guard let self else {
                return
            }
            self.session.select(index)
            self.window?.makeFirstResponder(self.canvas)
        }
        canvas.onLayout = { [weak self] scale, horizontal, vertical in
            self?.session.updateLayout(
                effectiveScale: scale,
                overflowsHorizontally: horizontal,
                overflowsVertically: vertical
            )
        }
        canvas.onNeedsPixels = { [weak self] pixels in
            self?.upgrade(to: pixels)
        }
        canvas.onZoom = { [weak self] zoom in
            self?.session.setZoom(zoom)
        }
        canvas.onClickSide = { [weak self] side in
            self?.session.dispatch(side > 0 ? .next : .previous)
        }
        canvas.contextMenu = {
            MainMenu.contextMenu()
        }
        canvas.onWheelStep = { [weak self] step in
            guard let self, self.session.state.config.wheel == .navigate else {
                return
            }
            self.session.dispatch(step > 0 ? .next : .previous)
        }
        window?.initialFirstResponder = canvas
        window?.makeFirstResponder(canvas)
    }

    private func installOverlays() {
        let hosting = PassthroughHostingView(rootView: OverlayView(model: overlay))
        // The overlay must never size the window; it fills whatever it gets.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(hosting, positioned: .above, relativeTo: canvas)
        outputPane.translatesAutoresizingMaskIntoConstraints = false
        outputPane.isHidden = true
        rootView.addSubview(outputPane)
        installHelp()
        prompt.translatesAutoresizingMaskIntoConstraints = false
        prompt.isHidden = true
        rootView.addSubview(prompt)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: rootView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            outputPane.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            outputPane.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            outputPane.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            prompt.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            prompt.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            prompt.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        canvas.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        prompt.onSubmit = { [weak self] text in
            self?.submitPrompt(text)
        }
        prompt.onCancel = { [weak self] in
            self?.endPrompt()
        }
        prompt.onTab = { [weak self] text, backwards in
            self?.completePrompt(text, backwards: backwards)
        }
    }

    var isEmpty: Bool { session.state.folder == nil }

    /// Header info of the file on the canvas, for the title and info overlay.
    var shownImageInfo: ImageInfo? { shownInfo }

    func open(_ url: URL) {
        session.open(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func settingsChanged() {
        session.applyConfig(AppModel.shared.config)
        rebuildMatcher()
    }

    func windowWillClose(_ notification: Notification) {
        upgradeTask?.cancel()
        animation.stop()
        folderWatcher = nil
        keyboard.slideshowTimer?.invalidate()
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(canvas)
    }

    // MARK: Rendering

    /// Re-renders whenever anything `render` reads changes.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
    }

    func render() {
        let state = session.state
        canvas.wheelZooms = state.config.wheel == .zoom
        canvas.clickNavigates = state.config.clickNavigates
        watchFolder(state.folder?.folder)
        canvas.apply(view: state.view, background: state.config.background)
        if state.current?.url != shownURL {
            load(state.current?.url)
            if let url = state.current?.url {
                AppModel.shared.noteViewed(url)
            }
            refreshQuickLook()
        }
        let title = WindowTitle.make(state: state, info: shownInfo)
        if window?.title != title {
            window?.title = title
            DebugLog.log("title \(title)")
        }
        if state.current == nil {
            rootView.message = emptyMessage(state)
        }
        renderOverlays(state)
        renderStrip(state)
        renderSidebar(state)
        renderMemo(state)
        renderHelp(state)
        applyTheatre(state.theatre)
    }

    /// `I` turns memos on; the pane shows whenever the folder has one, so
    /// walking cases with ] keeps it up where there is something to read.
    private func renderMemo(_ state: ViewerState) {
        let memo = state.memo ? state.folder.flatMap { Memo.url(for: $0.folder) } : nil
        let shows = memo != nil
        if memoPane.isHidden == shows {
            memoPane.isHidden = !shows
            canvasToRight?.isActive = !shows
            canvasToMemo?.isActive = shows
        }
        if let memo {
            memoPane.show(memo: memo, highlighting: state.current?.name)
        } else if state.memo, !keyboard.memoWasOn {
            showToast("memos on; \(state.folder?.folder.lastPathComponent ?? "this folder") has none")
        }
        keyboard.memoWasOn = state.memo
    }

    /// The key help over the window (SV-310): showing it hands it the
    /// keyboard, hiding it returns the keyboard to the sidebar or canvas.
    private func installHelp() {
        helpPane.translatesAutoresizingMaskIntoConstraints = false
        helpPane.isHidden = true
        rootView.addSubview(helpPane)
        // The window minus 24 pt on every side, so tall windows show more
        // rows and short ones scroll (FIXME-3).
        NSLayoutConstraint.activate([
            helpPane.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            helpPane.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            helpPane.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            helpPane.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -24),
        ])
        helpPane.onClose = { [weak self] in
            self?.session.dispatch(.help)
        }
        canvas.blocksInput = { [weak self] in
            self?.session.state.help ?? false
        }
        canvas.onBlockedClick = { [weak self] in
            self?.session.dispatch(.help)
        }
    }

    private func renderHelp(_ state: ViewerState) {
        guard helpPane.isHidden == state.help else {
            return
        }
        helpPane.isHidden = !state.help
        rootView.messageSuppressed = state.help
        if state.help {
            helpPane.show(AppModel.shared.keymap)
            window?.makeFirstResponder(helpPane)
        } else {
            DebugLog.log("help closed")
            window?.makeFirstResponder(state.sidebar ? sidebar : canvas)
        }
    }

    private func renderSidebar(_ state: ViewerState) {
        if sidebar.isHidden == state.sidebar {
            sidebar.isHidden = !state.sidebar
            canvasToLeft?.isActive = !state.sidebar
            canvasToSidebar?.isActive = state.sidebar
            // Showing the sidebar hands it the keyboard; hiding returns it.
            window?.makeFirstResponder(state.sidebar ? sidebar : canvas)
        }
        if state.sidebar {
            sidebar.load(state.folder?.folder)
        }
    }

    private func renderStrip(_ state: ViewerState) {
        if strip.isHidden == state.thumbnails {
            strip.isHidden = !state.thumbnails
            canvasToWindow?.isActive = !state.thumbnails
            canvasToStrip?.isActive = state.thumbnails
        }
        guard state.thumbnails else {
            return
        }
        strip.update(
            urls: state.visible.map(\.url),
            current: state.navigator.index,
            marked: state.marks.urls
        )
    }

    /// Theatre mode (SV-111): no title bar, the image to the window edges.
    private func applyTheatre(_ on: Bool) {
        guard let window, window.styleMask.contains(.fullSizeContentView) != on else {
            return
        }
        if on {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = on
        window.titleVisibility = on ? .hidden : .visible
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = on
        }
    }

    private func emptyMessage(_ state: ViewerState) -> String {
        if let folder = state.folder {
            return state.filter.isEmpty
                ? "\(folder.folder.lastPathComponent) has no images"
                : "no match for \(state.filter.pattern)"
        }
        return "Drop an image or folder here, or press : and type cd <path>"
    }

    // MARK: Folder watch

    /// Follows the shown folder on disk (SV-208): new captures appear in
    /// place, deleted files vanish, a replaced file is decoded again.
    private func watchFolder(_ folder: URL?) {
        guard folder?.path != watchedFolder?.path else {
            return
        }
        watchedFolder = folder
        folderWatcher = folder.flatMap { url in
            FSEventWatcher(url: url) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.folderChangedOnDisk()
                }
            }
        }
    }

    private func folderChangedOnDisk() {
        let changed = session.folderChangedOnDisk()
        DebugLog.log("folder changed, \(changed.count) files replaced")
        guard !changed.isEmpty else {
            return
        }
        Task { @MainActor in
            for url in changed {
                await pipeline.invalidate(url)
                strip.invalidate(url)
            }
            if let shown = shownURL, changed.contains(where: { $0.path == shown.path }) {
                shownURL = nil
                render()
            }
        }
    }

    // MARK: Loading

    private var windowPixels: Int {
        CanvasGeometry.windowPixelSize(
            viewSize: canvas.bounds.size == .zero ? NSSize(width: 1000, height: 700) : canvas.bounds.size,
            backingScale: window?.backingScaleFactor ?? 2
        )
    }

    /// Shows `url`: header first, any cached decode at once, then a
    /// window-size decode, then preloads the neighbours.
    private func load(_ url: URL?) {
        loadGeneration += 1
        let generation = loadGeneration
        upgradeTask?.cancel()
        animation.stop()
        shownURL = url
        shownInfo = nil
        guard let url else {
            canvas.show(nil, pixelSize: .zero, newFile: true)
            return
        }
        Task { @MainActor in
            do {
                let info = try await pipeline.info(url)
                guard generation == loadGeneration else {
                    return
                }
                shownInfo = info
                let size = CGSize(width: info.width, height: info.height)
                sizeWindow(toImage: size)
                let target = min(windowPixels, max(info.width, info.height))
                if let cached = await pipeline.cached(url, minPixelSize: target), generation == loadGeneration {
                    present(cached, size: size, newFile: true)
                } else {
                    let image = try await pipeline.image(url, maxPixelSize: windowPixels)
                    guard generation == loadGeneration else {
                        return
                    }
                    present(image, size: size, newFile: true)
                }
                if info.isAnimated {
                    animation.start(url, frameCount: info.frameCount)
                }
                render()
                preloadNeighbours()
            } catch {
                guard generation == loadGeneration else {
                    return
                }
                canvas.show(nil, pixelSize: .zero, newFile: true)
                rootView.message = "\(error)\nQuick Look may show it: cmd-y or :ql"
                render()
                preloadNeighbours()
            }
        }
    }

    private func present(
        _ image: CGImage,
        size: CGSize,
        newFile: Bool
    ) {
        rootView.message = nil
        canvas.show(image, pixelSize: size, newFile: newFile)
        if newFile {
            Bench.presented(session: session)
        }
        if !firstFrameLogged {
            firstFrameLogged = true
            Bench.firstFrame(in: rootView)
        }
    }

    /// `size_window_to_image` (SV-507): fit the window to the image at 1:1,
    /// shrunk to the screen, keeping its centre. Not in fullscreen.
    private func sizeWindow(toImage pixels: CGSize) {
        guard session.state.config.sizeWindowToImage,
            let window,
            !window.styleMask.contains(.fullScreen),
            let screen = window.screen ?? NSScreen.main
        else {
            return
        }
        let chrome = CGSize(
            width: (sidebar.isHidden ? 0 : SidebarView.width) + (memoPane.isHidden ? 0 : MemoPaneView.width),
            height: strip.isHidden ? 0 : ThumbnailStripView.height
        )
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let available = CGSize(width: screen.visibleFrame.width - 40, height: screen.visibleFrame.height - titleBar - 40)
        let content = WindowSizing.contentSize(
            imagePixels: pixels,
            backingScale: window.backingScaleFactor,
            chrome: chrome,
            available: available,
            minimum: window.contentMinSize.width > 0 ? window.contentMinSize : window.minSize
        )
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        let frame = WindowSizing.centred(frameSize, on: window.frame, within: screen.visibleFrame)
        window.setFrame(frame, display: true)
        DebugLog.log("window sized to \(Int(content.width))x\(Int(content.height))")
    }

    /// Replaces the decode with a sharper one when zoom needs more pixels.
    private func upgrade(to pixels: Int) {
        // Animated frames come from the player at full size already.
        guard !animation.isActive, let url = shownURL, let info = shownInfo else {
            return
        }
        let generation = loadGeneration
        upgradeTask?.cancel()
        upgradeTask = Task { @MainActor in
            guard let image = try? await pipeline.image(url, maxPixelSize: pixels),
                !Task.isCancelled,
                generation == loadGeneration,
                max(image.width, image.height) > canvas.decodedLongEdge
            else {
                return
            }
            present(image, size: CGSize(width: info.width, height: info.height), newFile: false)
        }
    }

    private func preloadNeighbours() {
        let state = session.state
        guard let index = state.navigator.index else {
            return
        }
        let indices = PreloadPlan.indices(
            around: index,
            count: state.visible.count,
            radius: state.config.preload,
            wraps: state.config.wrap
        )
        pipeline.preload(
            indices.map { state.visible[$0].url },
            maxPixelSize: windowPixels
        )
    }

    // MARK: Effects

    func perform(_ effect: Effect) {
        switch effect {
        case .pan(let dx, let dy):
            canvas.pan(dx: dx, dy: dy)
        case .prompt(let kind, let text):
            beginPrompt(kind, text: text)
        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .copyImage(let url):
            NSPasteboard.general.clearContents()
            if let image = NSImage(contentsOf: url) {
                NSPasteboard.general.writeObjects([image, url as NSURL])
            } else {
                showToast("cannot copy \(url.lastPathComponent)")
            }
        case .reveal(let urls):
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .openWith(let url):
            NSWorkspace.shared.open(url)
        case .newWindow(let url):
            (NSApp.delegate as? AppDelegate)?.newWindow(opening: url)
        case .compare(let left, let right):
            (NSApp.delegate as? AppDelegate)?.compare(left, right)
        case .toggleFullscreen:
            window?.toggleFullScreen(nil)
        case .exportMarked(let path, let names):
            exportMarked(names, to: path)
        case .quit:
            NSApp.terminate(nil)
        case .quickLook:
            toggleQuickLook()
        case .playPause:
            showToast(animation.togglePlaying() ?? "not an animated image")
        case .frameStep(let count):
            showToast(animation.step(count) ?? "not an animated image")
        case .runHook(let name):
            guard let command = session.state.config.hooks[name] else {
                showToast("no hook \(name): add `hook \(name) <command>` to the config")
                return
            }
            runHook(command)
        case .runShell(let line):
            runHook(line)
        case .exportConfig(let path):
            exportConfig(to: path)
        default:
            break
        }
    }

    /// `:export [path]` (SV-503): zips config and keymap off the main thread.
    private func exportConfig(to path: String) {
        let destination = ConfigArchive.sview.destination(for: path, folder: session.state.folder?.folder)
        let paths = AppModel.shared.paths
        Task { @MainActor in
            do {
                let names = try await ConfigArchive.sview.export(from: paths, to: destination)
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let shown = destination.path.hasPrefix(home) ? "~" + destination.path.dropFirst(home.count) : destination.path
                DebugLog.log("exported \(names.joined(separator: " ")) to \(destination.path)")
                showToast("exported \(names.count) files to \(shown)")
            } catch {
                showToast("\(error)")
            }
        }
    }

    /// Runs a hook command off the main thread and shows its output (SV-603).
    private func runHook(_ command: String) {
        let state = session.state
        outputPane.showRunning(command)
        Task { @MainActor in
            let result = await HookRunner.run(
                command,
                file: state.current?.url,
                folder: state.folder?.folder,
                marked: state.marks.ordered(in: state.visible).map(\.url)
            )
            DebugLog.log("hook exit \(result.status): \(result.output.prefix(200))")
            outputPane.show(result)
        }
    }

    /// SV-602: marked names to the clipboard, or to a file when a path is given.
    private func exportMarked(_ names: [String], to path: String) {
        guard !names.isEmpty else {
            showToast("nothing marked")
            return
        }
        let text = names.joined(separator: "\n") + "\n"
        guard !path.isEmpty else {
            perform(.copyText(text))
            showToast("copied \(names.count) names")
            return
        }
        let base = session.state.folder?.folder
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") || base == nil
            ? URL(fileURLWithPath: expanded)
            : base!.appendingPathComponent(expanded)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            showToast("wrote \(names.count) names to \(url.lastPathComponent)")
        } catch {
            showToast("cannot write \(url.lastPathComponent)")
        }
    }
}
