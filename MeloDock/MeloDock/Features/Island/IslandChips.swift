import SwiftUI

/// 28pt capsule used by the island's pickers and the Connect button.
struct IslandChipButtonStyle: ButtonStyle {
    /// White-filled with black text, for the Connect call to action.
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, prominent: prominent)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, prominent ? 12 : 10)
                .frame(height: 28)
                .foregroundStyle(prominent ? Color.black : IslandTheme.textPrimary)
                .background(Capsule(style: .continuous).fill(fill))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(IslandTheme.focusRing, lineWidth: 2)
                        .opacity(isFocused ? 1 : 0)
                )
                .contentShape(Capsule(style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : IslandTheme.dimmedOpacity)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var fill: Color {
            if prominent {
                return Color.white.opacity(configuration.isPressed ? 0.8 : (isHovering ? 0.9 : 1))
            }
            if configuration.isPressed { return IslandTheme.chipPressed }
            return isHovering ? IslandTheme.chipHover : IslandTheme.chipFill
        }
    }
}

/// Icon, label and an up/down chevron, laid out for a chip.
private struct ChipLabel: View {
    let systemImage: String
    let iconSize: CGFloat
    let title: String
    var maxTitleWidth: CGFloat?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxTitleWidth, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(IslandTheme.textSecondary)
        }
    }
}

/// Picks the music provider the island follows.
struct SourceChip: View {
    let selection: MusicProviderKind
    let onSelect: (MusicProviderKind) -> Void

    var body: some View {
        Menu {
            Picker("Music Source", selection: Binding(get: { selection }, set: onSelect)) {
                ForEach(MusicProviderKind.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            ChipLabel(systemImage: icon, iconSize: 12, title: selection.displayName)
        }
        .menuStyle(.button)
        .buttonStyle(IslandChipButtonStyle())
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .accessibilityLabel("Music source, \(selection.displayName)")
    }

    private var icon: String {
        switch selection {
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        }
    }
}

/// Picks the system audio output device.
struct OutputChip: View {
    private enum Layout {
        // 180pt chip minus padding, icon, chevron and gaps.
        static let maxTitleWidth: CGFloat = 124
    }

    let outputs: [AudioOutput]
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            if outputs.isEmpty {
                Button("No Outputs") {}
                    .disabled(true)
            } else {
                Picker("Audio Output", selection: Binding(get: { selectedID }, set: onSelect)) {
                    ForEach(outputs) { output in
                        Text(output.name).tag(output.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            ChipLabel(systemImage: "airplayaudio", iconSize: 14, title: selectedName,
                      maxTitleWidth: Layout.maxTitleWidth)
        }
        .menuStyle(.button)
        .buttonStyle(IslandChipButtonStyle())
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .accessibilityLabel("Audio output, \(selectedName)")
    }

    private var selectedName: String {
        if let selected = outputs.first(where: { $0.id == selectedID }) {
            return selected.name
        }
        return outputs.isEmpty ? "No Outputs" : "Output"
    }
}
