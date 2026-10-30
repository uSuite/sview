import AppKit
import Quartz

/// Quick Look passthrough (SV-405): `:ql` or cmd-y shows the system preview
/// of the current file, useful for types sView does not render. The window
/// controller sits in the responder chain, so the panel asks it for items.
extension ViewerWindowController: @preconcurrency QLPreviewPanelDataSource {
    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else {
            return
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            DebugLog.log("quick look hide")
            panel.orderOut(nil)
        } else {
            DebugLog.log("quick look show")
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        session.state.current == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        session.state.current?.url as NSURL?
    }

    /// Keeps an open panel on the current file as the viewer moves.
    func refreshQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else {
            return
        }
        panel.reloadData()
    }
}
