import AppKit
import Darwin
import ImageIO
import SViewCore

/// Hooks for `make bench` and `make smoke` (SV-701, SV-703). With
/// `SVIEW_BENCH=launch` the app prints the time from process start to the
/// first image on screen and quits. With `SVIEW_BENCH=browse` it steps
/// through the folder with `next` and prints the median and p95 time from
/// key to image, and the resident memory at the end. With `SVIEW_SNAPSHOT=<file.png>` it
/// renders the key window's layers to that file after the first image (or
/// after SVIEW_SNAPSHOT_DELAY seconds) and quits, which needs no Screen
/// Recording permission. Otherwise these are no-ops.
@MainActor
enum Bench {
    static let mode = ProcessInfo.processInfo.environment["SVIEW_BENCH"]

    static let snapshotPath = ProcessInfo.processInfo.environment["SVIEW_SNAPSHOT"]
    /// `SVIEW_WINDOW_SIZE=1200x760` opens windows at that content size, for
    /// screenshots that do not depend on the saved window frame.
    static var windowSize: NSSize? {
        guard let text = ProcessInfo.processInfo.environment["SVIEW_WINDOW_SIZE"] else {
            return nil
        }
        let parts = text.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : nil
    }
    /// Space-separated keymap key tokens posted to the window after the first
    /// image, e.g. `SVIEW_KEYS="5n gg i"`, so scripts can drive the viewer;
    /// the token `pause` waits half a second, `click@0.25` clicks a quarter
    /// of the way across and `wheel@-5` scrolls five lines down.
    static let keys = ProcessInfo.processInfo.environment["SVIEW_KEYS"]

    private static var stepStart: TimeInterval?
    private static var stepTimes: [Double] = []

    /// Called on every image put on screen; drives the browse benchmark.
    static func presented(session: Session) {
        guard mode == "browse" else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let start = stepStart {
            stepTimes.append((now - start) * 1000)
        }
        guard let position = session.state.position, position.index < position.count else {
            report()
            return
        }
        DispatchQueue.main.async {
            stepStart = ProcessInfo.processInfo.systemUptime
            session.dispatch(.next)
        }
    }

    private static func report() {
        let sorted = stepTimes.sorted()
        guard !sorted.isEmpty else {
            NSApp.terminate(nil)
            return
        }
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(String(format: "next-ms median %.1f p95 %.1f steps %d", median, p95, sorted.count))
        print(String(format: "rss-mb %.0f footprint-mb %.0f", residentMegabytes(), footprintMegabytes()))
        Task { @MainActor in
            let cache = AppModel.shared.pipeline.cache
            let cost = await cache.totalCost
            let count = await cache.count
            print("cache-mb \(cost / 1_048_576) entries \(count)")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    static func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    /// Physical footprint, the figure Activity Monitor shows as Memory.
    static func footprintMegabytes() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    // MARK: Keys smoke test

    /// Bindings the keys smoke test leaves out because they act outside the
    /// window: trash, clipboard, Finder, other apps, fullscreen, quit.
    static let keysSkipped: Set<Command> = [
        .quit, .fullscreen, .openWith, .reveal, .revealMarked, .trash, .trashMarked,
        .copyPath, .copyName, .copyImage, .copyMarked, .newWindow, .quickLook, .compare,
    ]
    private static var fired: [Command] = []

    static func recordFired(_ command: Command) {
        if mode == "keys" {
            fired.append(command)
        }
    }

    /// `SVIEW_BENCH=keys`: presses every default binding once and reports
    /// which commands did not fire (the Phase 3 binding check).
    private static func runKeys(in window: NSWindow) {
        let bindings = AppModel.shared.keymap.bindings.filter { !keysSkipped.contains($0.command) }
        Task { @MainActor in
            for binding in bindings {
                // Prompts and the sidebar take the keyboard and focus moves
                // on the next render, so wait until the canvas has it back.
                for _ in 0..<25 where !(window.firstResponder is ImageCanvasView) {
                    send(Key("esc"), to: window)
                    try? await Task.sleep(for: .milliseconds(40))
                }
                for key in binding.keys {
                    send(key, to: window)
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(500))
            let missing = bindings.filter { !fired.contains($0.command) }
            print("keys fired \(bindings.count - missing.count) of \(bindings.count)")
            for binding in missing {
                print("keys missing \(binding.keys.map(\.description).joined()) \(binding.text)")
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// A mouse-wheel scroll of `lines` (negative scrolls down) at the centre
    /// of the window, given to the view hit-testing finds there; the
    /// `wheel@-5` token of SVIEW_KEYS.
    private static func wheel(_ lines: Int32, in window: NSWindow) {
        guard let content = window.contentView,
            let target = content.hitTest(NSPoint(x: content.bounds.midX, y: content.bounds.midY)),
            let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: lines,
                wheel2: 0,
                wheel3: 0
            ),
            let event = NSEvent(cgEvent: cgEvent)
        else {
            return
        }
        DebugLog.log("wheel \(lines) on \(type(of: target))")
        target.scrollWheel(with: event)
    }

    /// A left click at `fraction` of the content width, mid height; the
    /// `click@0.25` token of SVIEW_KEYS.
    private static func click(at fraction: Double, in window: NSWindow) {
        guard let content = window.contentView else {
            return
        }
        let point = NSPoint(x: content.bounds.width * fraction, y: content.bounds.midY)
        // Synthetic mouse events are not routed by NSWindow the way real
        // ones are, so they go to the view hit-testing finds, which is the
        // part sView controls.
        guard let target = content.hitTest(point) else {
            return
        }
        DebugLog.log("click at \(point) on \(type(of: target))")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) {
                if type == .leftMouseDown {
                    target.mouseDown(with: event)
                } else {
                    target.mouseUp(with: event)
                }
            }
        }
    }

    private static func send(_ key: Key, to window: NSWindow) {
        if let event = KeyTranslator.event(for: key, in: window) {
            NSApp.sendEvent(event)
        }
    }

    static func firstFrame(in view: NSView) {
        if mode == "keys", let window = view.window {
            runKeys(in: window)
            return
        }
        if let keys, let window = view.window {
            post(keys, to: window)
        }
        if let path = snapshotPath {
            let wait = ProcessInfo.processInfo.environment["SVIEW_SNAPSHOT_DELAY"].flatMap(Double.init) ?? (keys == nil ? 0.5 : 1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                let front = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.contentView != nil }
                snapshot(front?.contentView ?? view, to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
            return
        }
        guard mode == "launch" else {
            return
        }
        // Wait for the frame to be committed to the screen, not just set.
        CATransaction.flush()
        DispatchQueue.main.async {
            let milliseconds = (Date().timeIntervalSince1970 - processStart()) * 1000
            print(String(format: "first-frame-ms %.1f", milliseconds))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    private static func post(_ text: String, to window: NSWindow) {
        let tokens = text.split(separator: " ").map(String.init)
        var delay = 0.0
        for token in tokens {
            // "pause" waits half a second, for async work such as listings.
            delay += token == "pause" ? 0.5 : 0.05
            if token == "pause" {
                continue
            }
            if token.hasPrefix("wheel@"), let lines = Int32(token.dropFirst(6)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    wheel(lines, in: window)
                }
                continue
            }
            if token.hasPrefix("click@"), let fraction = Double(token.dropFirst(6)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    click(at: fraction, in: window)
                }
                continue
            }
            let sequence = token == "space" ? [Key(" ")] : ((try? Key.parseSequence(token)) ?? [])
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // To whichever window has the keyboard now (a compare
                // window may have opened since).
                let target = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible } ?? window
                for key in sequence {
                    if let event = KeyTranslator.event(for: key, in: target) {
                        NSApp.sendEvent(event)
                    }
                }
            }
        }
    }

    /// Renders `view`'s layer tree at the backing scale into a PNG.
    static func snapshot(_ view: NSView, to url: URL) {
        guard let layer = view.layer else {
            return
        }
        let scale = view.window?.backingScaleFactor ?? 2
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return
        }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Process start time from the kernel, in seconds since 1970.
    static func processStart() -> TimeInterval {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else {
            return Date().timeIntervalSince1970
        }
        let start = info.kp_proc.p_un.__p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    }
}
