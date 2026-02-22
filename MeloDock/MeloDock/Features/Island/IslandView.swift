import SwiftUI

struct IslandView: View {
    private enum Theme {
        static let primaryText = Color.white.opacity(0.98)
        static let secondaryText = Color.white.opacity(0.72)
        static let panelTop = Color(red: 0.06, green: 0.06, blue: 0.07)
        static let panelBottom = Color(red: 0.01, green: 0.01, blue: 0.01)
        static let border = Color.white.opacity(0.07)
        static let topShine = Color.white.opacity(0.05)
        static let controlFill = Color.white.opacity(0.12)
        static let cornerRadius: CGFloat = 24
    }

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                artworkView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(viewModel.trackTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .layoutPriority(1)

                        if viewModel.shouldShowSpectrum {
                            MusicSpectrumView(
                                isActive: viewModel.playbackState.isPlaying,
                                seed: viewModel.spectrumSeed,
                                progress: viewModel.spectrumProgress,
                                tempoBPM: viewModel.spectrumTempoBPM
                            )
                            .frame(width: 76)
                        }
                    }

                    Text(viewModel.trackArtist)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

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

                if viewModel.authState != .authorized {
                    Button("Connect") {
                        viewModel.authorizeCurrentProvider()
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.controlFill)
                    )
                }
            }

            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.9))

            HStack {
                Text(viewModel.elapsedTimeText)
                Spacer()
                Text(viewModel.durationTimeText)
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 12) {
                PlayerControlsView(
                    isPlaying: viewModel.playbackState.isPlaying,
                    onPrevious: { viewModel.playPrevious() },
                    onPlayPause: { viewModel.togglePlayPause() },
                    onNext: { viewModel.playNext() }
                )

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    Slider(value: Binding(
                        get: { Double(viewModel.volume) },
                        set: { viewModel.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 130)

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
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 560, height: 156)
        .foregroundStyle(Theme.primaryText)
        .colorScheme(.dark)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.panelTop, Theme.panelBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Theme.topShine, lineWidth: 1)
                .blur(radius: 0.4)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 9)
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.99))
                .frame(width: 186, height: 16)
                .offset(y: -8)
        }
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
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholderArtwork
                .frame(width: 54, height: 54)
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.90))
            )
    }
}
