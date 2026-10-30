import SCommon

/// sView's keymap and matcher: the shared generic ones over `Command`.
public typealias Keymap = SCommon.Keymap<Command>
public typealias KeyMatcher = SCommon.KeyMatcher<Command>

extension Command: KeymapCommand {}

extension SCommon.Keymap where C == Command {
    /// The shipped bindings (SV-301), copied to the config directory on
    /// first run as documentation.
    public static var defaultText: String { DefaultKeymap.text }

    public static var `default`: Keymap { DefaultKeymap.keymap }

    /// The user's keymap file applied over the shipped defaults (SV-504).
    public static func overlaid(_ userText: String) -> (keymap: Keymap, issues: [LineIssue]) {
        overlaid(userText, over: .default)
    }
}

/// Stored once: static stored properties cannot live in an extension of a
/// generic type.
enum DefaultKeymap {
    static let keymap = Keymap.parse(text).keymap

    static let text = """
        # sView keymap. One binding per line: <keys> <command> [args]
        # Lines here apply over the built-in defaults; `<keys> nop` unbinds one.
        # Keys are characters (case matters) or named keys: space enter tab esc
        # backspace delete left right up down home end pageup pagedown f1..f12
        # hash lt gt, with cmd- ctrl- alt- shift- modifiers. Use <name> inside a
        # sequence, e.g. g<space>. A number before a key repeats it: 5n, 20G.
        # :map <keys> <command> appends here.

        # sequence
        n next
        p previous
        N previous
        space next
        shift-space previous
        gg first
        G last
        # h j k l and arrows pan when the image overflows, else navigate
        h left
        j down
        k up
        l right
        left left
        down down
        up up
        right right
        home first
        end last

        # view
        + zoom-in
        - zoom-out
        = zoom-fit
        e zoom-actual
        w zoom-width
        W zoom-height
        lt rotate-left
        gt rotate-right
        | flip-horizontal
        _ flip-vertical
        f fullscreen
        F theatre
        T toggle-title
        i info
        I memo
        t thumbnails
        s sidebar
        ? help
        r reload
        enter slideshow
        a play-pause
        ctrl-n frame-next
        ctrl-p frame-previous

        # folders
        ] folder-next
        [ folder-previous
        backspace folder-parent
        gu folder-parent
        o folder-enter
        gr recursive

        # filter, marks, files
        / filter-prompt
        esc cancel
        m mark
        M mark-all
        ' mark-next
        " mark-previous
        yy copy-path
        yn copy-name
        yi copy-image
        ym copy-marked
        R reveal
        O open-with
        dd trash
        D trash-marked
        u undo
        cw rename-prompt
        C compare

        # other
        : command-line
        . repeat
        q quit

        """
}
