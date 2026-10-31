import SwiftUI

/// Compact ears for now playing: artwork on the leading ear, spectrum (or the network speed) on the trailing ear.
struct CompactNowPlayingView: View {
    private enum Layout {
        static let artworkSize: CGFloat = 22
        // MusicSpectrumView is ~70pt wide at full size; scale it to fit inside the ear.
        static let spectrumScale: CGFloat = 0.6
    }

    @ObservedObject var viewModel: IslandViewModel
    /// Set while the network speed is switched on: it takes the trailing ear in place of the spectrum.
    var networkModel: NetworkSpeedModel?

    var body: some View {
        HStack(spacing: 0) {
            NowPlayingArtworkView(url: viewModel.artworkURL, cornerRadius: 6, placeholderIconSize: 10)
                .frame(width: Layout.artworkSize, height: Layout.artworkSize)
                .frame(width: IslandShapeMetrics.earWidth)

            Spacer(minLength: 0)

            if let networkModel {
                CompactNetworkStackView(model: networkModel)
            } else {
                MusicSpectrumView(
                    isActive: viewModel.playbackState.isPlaying,
                    seed: viewModel.spectrumSeed,
                    progress: viewModel.spectrumProgress,
                    tempoBPM: viewModel.spectrumTempoBPM
                )
                .fixedSize()
                .scaleEffect(Layout.spectrumScale)
                .frame(width: IslandShapeMetrics.earWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
