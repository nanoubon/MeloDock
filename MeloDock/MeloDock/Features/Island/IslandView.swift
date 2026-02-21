import SwiftUI

struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                artworkView

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.trackTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(viewModel.trackArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.9))

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
        .frame(width: 560, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
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
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholderArtwork
                .frame(width: 54, height: 54)
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.8))
            )
    }
}
