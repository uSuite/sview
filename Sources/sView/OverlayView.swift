import Observation
import SwiftUI

/// What the SwiftUI overlay draws; the window controller fills it in.
@MainActor
@Observable
final class OverlayModel {
    var toast: String?
    var pendingKeys = ""
    var infoLines: [String] = []
}

/// Non-interactive overlays over the canvas (SV-401, SV-406): info panel,
/// toast and pending keys. Clicks pass through; the `?` key list is the
/// HelpPaneView, which takes input.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack {
            if !model.infoLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.infoLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
            if !model.pendingKeys.isEmpty {
                Text(model.pendingKeys)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.toast)
        .allowsHitTesting(false)
    }
}

/// Hosts the overlay without taking clicks: every hit falls through to the
/// canvas below, so click, double-click, drag and right-click reach it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
