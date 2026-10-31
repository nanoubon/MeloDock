import SwiftUI

/// Compact ears for now playing. Alone, it is artwork on the leading ear and the spectrum on the trailing ear.
/// With the network speed on, the leading ear holds the artwork and a small spectrum and the speed takes the trailing ear.
struct CompactNowPlayingView: View {
    private enum Layout {
        static let artworkSize: CGFloat = 22
        // MusicSpectrumView is ~70pt wide at full size; scale it to fit inside the ear.
        static let spectrumScale: CGFloat = 0.6
        /// Inset of the artwork from the island's outer edge, and its gap to the small spectrum.
        static let sharedLeadingInset: CGFloat = 14
        static let sharedGap: CGFloat = 7
    }

    @ObservedObject var viewModel: IslandViewModel
    /// Set while the network speed is switched on: it takes the trailing ear and the spectrum moves beside the artwork.
    var networkModel: NetworkSpeedModel?

    var body: some View {
        HStack(spacing: 0) {
            if networkModel != nil {
                HStack(spacing: Layout.sharedGap) {
                    artwork
                    spectrum(barCount: 5, barWidth: 2.6, barSpacing: 2)
                }
                .padding(.leading, Layout.sharedLeadingInset)
                .frame(width: IslandShapeMetrics.musicNetworkEarWidth, alignment: .leading)
            } else {
                artwork
                    .frame(width: IslandShapeMetrics.earWidth)
            }

            Spacer(minLength: 0)

            if let networkModel {
                CompactNetworkStackView(model: networkModel, earWidth: IslandShapeMetrics.musicNetworkEarWidth)
            } else {
                spectrum()
                    .scaleEffect(Layout.spectrumScale)
                    .frame(width: IslandShapeMetrics.earWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var artwork: some View {
        NowPlayingArtworkView(url: viewModel.artworkURL, cornerRadius: 6, placeholderIconSize: 10)
            .frame(width: Layout.artworkSize, height: Layout.artworkSize)
    }

    private func spectrum(barCount: Int = 14, barWidth: CGFloat = 2.8, barSpacing: CGFloat = 2.4) -> some View {
        MusicSpectrumView(
            isActive: viewModel.playbackState.isPlaying,
            seed: viewModel.spectrumSeed,
            progress: viewModel.spectrumProgress,
            tempoBPM: viewModel.spectrumTempoBPM,
            levels: viewModel.spectrumLevels,
            barCount: barCount,
            barWidth: barWidth,
            barSpacing: barSpacing
        )
        .fixedSize()
    }
}
