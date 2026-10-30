import AppKit
import SViewCore

/// Keyboard, prompt and overlay plumbing for the viewer window (SV-301,
/// SV-302, SV-304, SV-401, SV-406). State lives in `KeyboardState`, owned by
/// the controller.
@MainActor
final class KeyboardState {
    var matcher = KeyMatcher(keymap: AppModel.shared.keymap)
    var timeout: Task<Void, Never>?
    var prompt: Effect.Prompt?
    var toastTask: Task<Void, Never>?
    var lastSessionToast: String?
    var lastZoom: ViewState.Zoom?
    var slideshowTimer: Timer?
    /// Tab cycling state: the candidates and which one is shown.
    var completion: (candidates: [String], index: Int)?
    /// Whether memos were on at the last render, to toast only on `I`.
    var memoWasOn = false
}

extension ViewerWindowController {
    /// vim's timeoutlen: how long an ambiguous prefix waits for the next key.
    static let keyTimeout: Duration = .milliseconds(1000)

    func handleKey(_ event: NSEvent) -> Bool {
        guard keyboard.prompt == nil, let key = KeyTranslator.key(for: event) else {
            return false
        }
        // Esc first closes the hook output pane.
        if key == Key("esc"), !keyboard.matcher.isPending, !outputPane.isHidden {
            outputPane.isHidden = true
            return true
        }
        DebugLog.log("key \(key)")
        keyboard.timeout?.cancel()
        let wasPending = keyboard.matcher.isPending
        let result = keyboard.matcher.feed(key)
        overlay.pendingKeys = keyboard.matcher.display
        switch result {
        case .matched(let invocation):
            DebugLog.log("command \(invocation.command.text)")
            Bench.recordFired(invocation.command)
            session.dispatch(invocation)
            return true
        case .pending:
            keyboard.timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.keyTimeout)
                guard let self, !Task.isCancelled else {
                    return
                }
                let flushed = self.keyboard.matcher.flush()
                self.overlay.pendingKeys = ""
                if let flushed {
                    Bench.recordFired(flushed.command)
                    self.session.dispatch(flushed)
                }
            }
            return true
        case .unmatched:
            // Unbound command-key combinations go on to the menus and system.
            return wasPending || !key.modifiers.contains(.command)
        }
    }

    func rebuildMatcher() {
        keyboard.matcher = KeyMatcher(keymap: AppModel.shared.keymap)
        overlay.pendingKeys = ""
    }

    // MARK: Prompt

    func beginPrompt(_ kind: Effect.Prompt, text: String) {
        keyboard.prompt = kind
        switch kind {
        case .command:
            prompt.begin(prefix: ":", text: text)
        case .filter:
            prompt.begin(prefix: "/", text: text)
        case .rename:
            prompt.begin(prefix: "rename:", text: text)
        }
    }

    /// Tab in the `:` prompt: complete a single match, extend to the common
    /// prefix, then cycle through the matches (SV-304).
    func completePrompt(_ text: String, backwards: Bool) -> String? {
        guard keyboard.prompt == .command else {
            return nil
        }
        if var cycle = keyboard.completion, cycle.candidates.contains(text) {
            let count = cycle.candidates.count
            cycle.index = (cycle.index + (backwards ? count - 1 : 1)) % count
            keyboard.completion = cycle
            return cycle.candidates[cycle.index]
        }
        keyboard.completion = nil
        let candidates = Completer.complete(
            text,
            folder: session.state.folder?.folder,
            hooks: Array(session.state.config.hooks.keys)
        )
        guard !candidates.isEmpty else {
            showToast("no completion")
            return nil
        }
        if candidates.count == 1 {
            return candidates[0]
        }
        let shown = candidates.prefix(8).map { candidate in
            String(candidate.split(separator: " ").last ?? Substring(candidate))
        }
        showToast(shown.joined(separator: "  ") + (candidates.count > 8 ? "  …" : ""))
        let prefix = Completer.commonPrefix(candidates)
        if prefix.count > text.count {
            return prefix
        }
        let index = backwards ? candidates.count - 1 : 0
        keyboard.completion = (candidates, index)
        return candidates[index]
    }

    func endPrompt() {
        keyboard.completion = nil
        keyboard.prompt = nil
        prompt.end()
        window?.makeFirstResponder(canvas)
    }

    func submitPrompt(_ text: String) {
        let kind = keyboard.prompt
        endPrompt()
        switch kind {
        case .command:
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                return
            }
            do {
                session.dispatch(try Command.parseCommandLine(text))
            } catch {
                showToast(error.description)
            }
        case .filter:
            session.dispatch(text.isEmpty ? .filterClear : .filter(text))
        case .rename:
            session.dispatch(.rename(text))
        case nil:
            break
        }
    }

    // MARK: Overlays

    func renderOverlays(_ state: ViewerState) {
        if state.toast != keyboard.lastSessionToast {
            keyboard.lastSessionToast = state.toast
            if let toast = state.toast {
                showToast(toast)
            }
        }
        if state.view.zoom != keyboard.lastZoom {
            if keyboard.lastZoom != nil, case .scale(let scale) = state.view.zoom {
                showToast("zoom \(Int((scale * 100).rounded()))%")
            }
            keyboard.lastZoom = state.view.zoom
        }
        overlay.infoLines = InfoText.lines(level: state.info, state: state, info: shownImageInfo)
        updateSlideshow(state)
    }

    /// Shows `message` for a moment; session toasts are cleared afterwards.
    func showToast(_ message: String) {
        DebugLog.log("toast \(message)")
        overlay.toast = message
        keyboard.toastTask?.cancel()
        keyboard.toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled else {
                return
            }
            self.overlay.toast = nil
            if self.session.state.toast != nil {
                self.session.clearToast()
            }
        }
    }

    private func updateSlideshow(_ state: ViewerState) {
        if state.slideshow, keyboard.slideshowTimer == nil {
            keyboard.slideshowTimer = Timer.scheduledTimer(
                withTimeInterval: state.config.slideshowSeconds,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.session.slideshowTick()
                }
            }
        } else if !state.slideshow, let timer = keyboard.slideshowTimer {
            timer.invalidate()
            keyboard.slideshowTimer = nil
        }
    }
}

/// Info overlay text (SV-401): off, compact or full.
enum InfoText {
    static func lines(
        level: InfoLevel,
        state: ViewerState,
        info: ImageInfo?
    ) -> [String] {
        guard level != .off, let item = state.current, let position = state.position else {
            return []
        }
        var lines = ["\(item.name)  \(position.index)/\(position.count)"]
        var size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        if let info {
            size = "\(info.width) x \(info.height)  " + size
        }
        lines.append(size + "  zoom \(Int((state.view.effectiveScale * 100).rounded()))%")
        guard level == .full else {
            return lines
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        lines.append("modified \(formatter.string(from: item.modified))")
        if let info {
            if let taken = info.dateTaken {
                lines.append("taken \(taken)")
            }
            let colour = [info.colorModel, info.profileName, info.bitDepth.map { "\($0)-bit" }]
                .compactMap { $0 }
                .joined(separator: " ")
            if !colour.isEmpty {
                lines.append(colour + (info.hasAlpha ? " alpha" : ""))
            }
            if info.isAnimated {
                lines.append("\(info.frameCount) frames")
            }
            if let camera = info.camera {
                lines.append(camera)
            }
            if let lens = info.lens {
                lines.append(lens)
            }
            if let exposure = info.exposure {
                lines.append(exposure)
            }
            lines.append("GPS " + (info.hasGPS ? "yes" : "no"))
        }
        lines.append(item.url.deletingLastPathComponent().path)
        return lines
    }
}

extension ViewerWindowController {
    /// Menu bar items carry their `Command` (SV-501).
    @objc func performMenuCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else {
            return
        }
        if keyboard.prompt != nil {
            endPrompt()
        }
        session.dispatch(box.command)
    }
}
