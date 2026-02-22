import SwiftUI

struct IslandView: View {
    private enum Layout {
        static let panelWidth: CGFloat = 612
        static let panelHeight: CGFloat = 176
        static let cornerRadius: CGFloat = 26
        static let outerPadding: CGFloat = 16
        static let blockSpacing: CGFloat = 10
        static let compactSpacing: CGFloat = 8
        static let controlHeight: CGFloat = 40
        static let albumSize: CGFloat = 60
        static let titleSize: CGFloat = 17
        static let subtitleSize: CGFloat = 13
        static let spectrumWidth: CGFloat = 72
    }

    private enum Theme {
        static let textPrimary = Color.white.opacity(0.98)
        static let textSecondary = Color.white.opacity(0.76)
        static let textTertiary = Color.white.opacity(0.54)
        static let panelTop = Color(red: 0.07, green: 0.08, blue: 0.10)
        static let panelBottom = Color(red: 0.01, green: 0.01, blue: 0.02)
        static let panelBorder = Color.white.opacity(0.08)
        static let panelGlow = Color(red: 0.53, green: 0.74, blue: 1.0).opacity(0.20)
        static let fieldFill = Color.white.opacity(0.09)
        static let fieldStroke = Color.white.opacity(0.13)
        static let progressTrack = Color.white.opacity(0.16)
        static let progressFill = Color.white.opacity(0.92)
        static let scrubber = Color.white
    }

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            topRow
            progressSection
            bottomRow
        }
        .padding(.horizontal, Layout.outerPadding)
        .padding(.vertical, Layout.outerPadding)
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .foregroundStyle(Theme.textPrimary)
        .colorScheme(.dark)
        .background(panelBackground)
        .clipShape(panelShape, style: FillStyle(eoFill: false, antialiased: true))
        .overlay(panelBorderOverlay)
        .overlay(panelGlowOverlay)
    }

    private var topRow: some View {
        HStack(spacing: Layout.blockSpacing) {
            artworkView
                .frame(width: Layout.albumSize, height: Layout.albumSize)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(viewModel.trackTitle)
                        .font(.system(size: Layout.titleSize, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)

                    if viewModel.shouldShowSpectrum {
                        MusicSpectrumView(
                            isActive: viewModel.playbackState.isPlaying,
                            seed: viewModel.spectrumSeed,
                            progress: viewModel.spectrumProgress,
                            tempoBPM: viewModel.spectrumTempoBPM
                        )
                        .frame(width: Layout.spectrumWidth)
                        .offset(y: 1)
                    }
                }

                Text(viewModel.trackArtist)
                    .font(.system(size: Layout.subtitleSize, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Layout.compactSpacing)

            HStack(spacing: Layout.compactSpacing) {
                sourcePicker
                if viewModel.authState != .authorized {
                    Button("Connect") {
                        viewModel.authorizeCurrentProvider()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: Layout.controlHeight)
                    .background(fieldCapsule())
                }
            }
        }
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.selectedProvider },
            set: { viewModel.setProvider($0) }
        )) {
            ForEach(MusicProviderKind.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(minWidth: 168)
        .frame(height: Layout.controlHeight)
        .background(fieldCapsule())
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            progressBar

            HStack {
                Text(viewModel.elapsedTimeText)
                Spacer()
                Text(viewModel.durationTimeText)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = min(max(CGFloat(viewModel.progressFraction), 0), 1)
            let filledWidth = progress > 0 ? max(8, width * progress) : 0
            let knobX = min(max(5.5, width * progress), width - 5.5)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.progressTrack)
                    .frame(height: 5)

                Capsule(style: .continuous)
                    .fill(Theme.progressFill)
                    .frame(width: filledWidth, height: 5)

                Circle()
                    .fill(Theme.scrubber)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.32), radius: 2.2, x: 0, y: 1)
                    .offset(x: knobX - 5.5)
            }
        }
        .frame(height: 10)
    }

    private var bottomRow: some View {
        HStack(spacing: Layout.blockSpacing) {
            PlayerControlsView(
                isPlaying: viewModel.playbackState.isPlaying,
                onPrevious: { viewModel.playPrevious() },
                onPlayPause: { viewModel.togglePlayPause() },
                onNext: { viewModel.playNext() }
            )

            Spacer(minLength: Layout.compactSpacing)

            volumeCluster
            outputPicker
        }
    }

    private var volumeCluster: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Slider(value: Binding(
                get: { Double(viewModel.volume) },
                set: { viewModel.setVolume(Float($0)) }
            ), in: 0...1)
            .tint(.white.opacity(0.9))
            .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.controlHeight)
        .background(fieldCapsule())
    }

    private var outputPicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.selectedOutputID },
            set: { viewModel.chooseOutput($0) }
        )) {
            if viewModel.outputs.isEmpty {
                Text("No Outputs").tag("")
            } else {
                ForEach(viewModel.outputs) { output in
                    Text(output.name).tag(output.id)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(width: 192, height: Layout.controlHeight)
        .background(fieldCapsule())
    }

    private var panelBackground: some View {
        panelShape
            .fill(
                LinearGradient(
                    colors: [Theme.panelTop, Theme.panelBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var panelBorderOverlay: some View {
        panelShape
            .strokeBorder(Theme.panelBorder, lineWidth: 1, antialiased: true)
    }

    private var panelGlowOverlay: some View {
        panelShape
            .strokeBorder(Theme.panelGlow.opacity(0.7), lineWidth: 1, antialiased: true)
    }

    private func fieldCapsule() -> some View {
        Capsule(style: .continuous)
            .fill(Theme.fieldFill)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.fieldStroke, lineWidth: 1, antialiased: true)
            )
    }

    @ViewBuilder
    private var artworkView: some View {
        if let url = viewModel.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderArtwork
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.11))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1, antialiased: true)
            )
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
    }
}
