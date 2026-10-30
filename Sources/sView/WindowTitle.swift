import Foundation
import SViewCore

/// The title bar text (SV-111, SV-601): `name  i/N  WxH  size`, with the PoC
/// case and step in front when the folder is a case folder.
enum WindowTitle {
    static func make(
        state: ViewerState,
        info: ImageInfo?
    ) -> String {
        guard state.showTitle else {
            return ""
        }
        guard let item = state.current, let position = state.position else {
            return state.folder?.folder.lastPathComponent ?? "sView"
        }
        var parts = [item.name, "\(position.index)/\(position.count)"]
        if let info {
            parts.append("\(info.width)x\(info.height)")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        if !state.marks.isEmpty {
            parts.append(state.marks.contains(item.url) ? "marked \(state.marks.count)" : "\(state.marks.count) marked")
        }
        if !state.filter.isEmpty {
            parts.append("/\(state.filter.pattern)")
        }
        let folderName = item.url.deletingLastPathComponent().lastPathComponent
        if let poc = PocCase(folderName: folderName), let step = poc.step(fileName: item.name) {
            parts.insert("\(poc.caseID)  \(step)", at: 0)
        }
        return parts.joined(separator: "  ")
    }
}
