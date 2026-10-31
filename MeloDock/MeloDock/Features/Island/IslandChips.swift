import SwiftUI

/// 28pt capsule used by the timer and calendar pages.
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

/// 28pt uppercase text link used by the expanded player's source and output pickers and its Connect action:
/// no fill at rest, a faint rounded background on hover.
struct IslandLinkButtonStyle: ButtonStyle {
    /// Accent-colored text, for the Connect call to action.
    var accent = false

    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration, accent: accent)
    }

    private struct LinkBody: View {
        private enum Layout {
            static let height: CGFloat = 28
            static let horizontalPadding: CGFloat = 6
            static let cornerRadius: CGFloat = 8
        }

        let configuration: ButtonStyleConfiguration
        let accent: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
            configuration.label
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .padding(.horizontal, Layout.horizontalPadding)
                .frame(height: Layout.height)
                .foregroundStyle(foreground)
                .background(shape.fill(isHovering || configuration.isPressed ? IslandTheme.linkHover : .clear))
                .overlay(shape.strokeBorder(IslandTheme.focusRing, lineWidth: 2).opacity(isFocused ? 1 : 0))
                .contentShape(shape)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : IslandTheme.dimmedOpacity)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var foreground: Color {
            if accent { return IslandTheme.accent }
            return isHovering || configuration.isPressed ? IslandTheme.textPrimary : IslandTheme.textSecondary
        }
    }
}

/// Optional icon, title and a down chevron, laid out for a text link.
private struct LinkLabel: View {
    var systemImage: String?
    let title: String
    /// Caps the title and chevron together; a truncated title leaves any slack after the chevron, not before it.
    var maxTitleWidth: CGFloat?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
            }
            .frame(maxWidth: maxTitleWidth, alignment: .leading)
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
            LinkLabel(title: selection.displayName)
        }
        .menuStyle(.button)
        .buttonStyle(IslandLinkButtonStyle())
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .accessibilityLabel("Music source, \(selection.displayName)")
    }
}

/// Picks the system audio output device.
struct OutputChip: View {
    let outputs: [AudioOutput]
    let selectedID: String
    /// Caps the device name (plus chevron) so long names truncate instead of crowding the row. Nil shows it in full.
    var maxTitleWidth: CGFloat?
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
            LinkLabel(systemImage: icon, title: selectedName, maxTitleWidth: maxTitleWidth)
        }
        .menuStyle(.button)
        .buttonStyle(IslandLinkButtonStyle())
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .accessibilityLabel("Audio output, \(selectedName)")
    }

    private var selected: AudioOutput? {
        outputs.first(where: { $0.id == selectedID })
    }

    private var icon: String {
        selected?.isBluetooth == true ? "headphones" : "hifispeaker.fill"
    }

    private var selectedName: String {
        if let selected {
            return selected.name
        }
        return outputs.isEmpty ? "No Outputs" : "Output"
    }
}
