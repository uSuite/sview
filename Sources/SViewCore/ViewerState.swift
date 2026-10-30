import Foundation

/// A command with its vim count prefix: the shared generic over `Command`.
public typealias Invocation = SCommon.Invocation<Command>

/// How the current image is shown. Rotation and flips are view-only (SV-107).
public struct ViewState: Sendable, Equatable {
    public enum Zoom: Sendable, Equatable {
        case fit
        case width
        case height
        case actual
        case scale(Double)
    }

    public static let zoomStep = 1.25
    public static let scaleRange = 0.02...64.0

    public var zoom: Zoom
    /// Image pixels per screen point actually shown; written by the canvas
    /// after layout so relative zoom starts from what the user sees.
    public var effectiveScale: Double = 1
    /// Clockwise quarter turns, 0 to 3.
    public var quarterTurns = 0
    public var flippedHorizontally = false
    public var flippedVertically = false

    public init(zoom: Zoom = .fit) {
        self.zoom = zoom
    }

    public init(mode: Config.ZoomMode) {
        switch mode {
        case .fit:
            zoom = .fit
        case .width:
            zoom = .width
        case .height:
            zoom = .height
        case .actual:
            zoom = .actual
        }
    }

    public var isRotatedSideways: Bool { quarterTurns % 2 == 1 }
}

public enum InfoLevel: Int, Sendable, CaseIterable {
    case off
    case compact
    case full

    public var next: InfoLevel { InfoLevel(rawValue: (rawValue + 1) % 3) ?? .off }
}

/// Everything the UI renders, mutated only by `Dispatcher` and `Session`.
public struct ViewerState: Sendable, Equatable {
    public private(set) var folder: FolderModel?
    public private(set) var filter = Filter("")
    public private(set) var visible: [ImageItem] = []
    public private(set) var navigator = Navigator(count: 0)
    public var marks = Marks()
    public var config: Config
    public var view: ViewState
    /// Whether the shown image overflows the window, written by the canvas;
    /// decides if h j k l pan or navigate.
    public var overflowsHorizontally = false
    public var overflowsVertically = false
    public var info = InfoLevel.off
    public var thumbnails = false
    public var sidebar = false
    public var memo = false
    public var help = false
    public var theatre = false
    public var slideshow = false
    public var showTitle: Bool
    public var toast: String?
    public var lastRepeatable: Invocation?

    public init(config: Config = Config()) {
        self.config = config
        view = ViewState(mode: config.zoom)
        showTitle = config.showTitle
        navigator.wraps = config.wrap
    }

    public var current: ImageItem? {
        navigator.index.map { visible[$0] }
    }

    /// One-based position and total for the title (`i/N`).
    public var position: (index: Int, count: Int)? {
        navigator.position.map { ($0, visible.count) }
    }

    public mutating func setFolder(
        _ model: FolderModel,
        selecting url: URL? = nil
    ) {
        let sameFolder = folder?.folder.path == model.folder.path
        folder = model
        if !sameFolder {
            filter = Filter("")
        }
        // A different folder without a chosen file starts at its first image.
        refresh(
            keeping: url ?? (sameFolder ? current?.url : nil),
            fallback: sameFolder ? navigator.index : 0
        )
    }

    public mutating func setFilter(_ newFilter: Filter) {
        let keep = current?.url
        filter = newFilter
        refresh(keeping: keep, fallback: navigator.index)
    }

    public mutating func setConfig(_ newConfig: Config) {
        let resort = newConfig.sort != config.sort
        config = newConfig
        navigator.wraps = newConfig.wrap
        if resort, var model = folder {
            model.sort(by: newConfig.sort)
            setFolder(model)
        }
    }

    /// Moves to `index` in `visible`, resetting per-image view state when the
    /// image changes.
    public mutating func select(_ index: Int) {
        let before = current?.url
        navigator.jump(to: index)
        if current?.url != before {
            resetView()
        }
    }

    mutating func moveNavigator(_ body: (inout Navigator) -> Void) {
        let before = current?.url
        body(&navigator)
        if current?.url != before {
            resetView()
        }
    }

    public mutating func resetView() {
        view = ViewState(mode: config.zoom)
    }

    /// Rebuilds `visible` from the folder and filter, staying on `url` when it
    /// is still visible, else on `fallback` clamped into range.
    private mutating func refresh(
        keeping url: URL?,
        fallback: Int?
    ) {
        let before = current?.url
        visible = folder.map { filter.apply(to: $0.items) } ?? []
        let target = url.flatMap { wanted in
            visible.firstIndex { $0.url.path == wanted.path }
        }
        navigator.reset(count: visible.count, index: target ?? fallback)
        if current?.url != before {
            resetView()
        }
    }
}
