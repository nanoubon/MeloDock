import SwiftUI

/// Which indicator glyph goes on which ear while an app records.
enum CaptureEars {
    enum Glyph: Equatable { case mic, camera }

    /// Both active: camera leads, mic trails. A single indicator sits on the trailing ear, where iOS puts its dot.
    static func glyphs(mic: Bool, camera: Bool) -> (leading: Glyph?, trailing: Glyph?) {
        switch (mic, camera) {
        case (true, true): (.camera, .mic)
        case (true, false): (nil, .mic)
        case (false, true): (nil, .camera)
        case (false, false): (nil, nil)
        }
    }
}

/// Compact ears for microphone / camera in use: orange mic and green camera, as on iOS.
struct CompactCaptureView: View {
    let mic: Bool
    let camera: Bool

    var body: some View {
        let ears = CaptureEars.glyphs(mic: mic, camera: camera)
        HStack(spacing: 0) {
            ear(ears.leading)
            Spacer(minLength: 0)
            ear(ears.trailing)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch (mic, camera) {
        case (true, true): "Camera and microphone in use"
        case (true, false): "Microphone in use"
        case (false, true): "Camera in use"
        case (false, false): ""
        }
    }

    @ViewBuilder
    private func ear(_ glyph: CaptureEars.Glyph?) -> some View {
        Group {
            if let glyph {
                CaptureDot(glyph: glyph)
            } else {
                Color.clear
            }
        }
        .frame(width: IslandShapeMetrics.earWidth)
    }
}

/// A small colored dot with its glyph.
struct CaptureDot: View {
    let glyph: CaptureEars.Glyph
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(glyph == .mic ? Color.orange : Color.green)
            Image(systemName: glyph == .mic ? "mic.fill" : "video.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        }
        .frame(width: size, height: size)
    }
}
