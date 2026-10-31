import SwiftUI

/// Compact ears for now playing. Alone, the artwork fills the leading ear and fades out toward the notch, and an
/// accent spectrum takes the trailing ear. With the network speed on, the leading ear holds a small artwork and a
/// small spectrum and the speed takes the trailing ear.
struct CompactNowPlayingView: View {
    private enum Layout {
        /// Leading-ear artwork: a square this wide, raised a little, filling the ear height. It runs past the
        /// 56pt ear under the hardware notch, where it has already faded out.
        static let earArtworkWidth: CGFloat = 72
        static let earArtworkRaise: CGFloat = 6
        /// Horizontal fade: opaque up to this fraction of the artwork, clear at its trailing edge.
        static let earArtworkFadeStart: CGFloat = 0.45
        static let earPlaceholderGlyphSize: CGFloat = 11
        /// Placeholder glyph center within the 72pt square, inside the visible, opaque part.
        static let earPlaceholderGlyphCenter = UnitPoint(x: 0.25, y: 0.3)

        static let artworkSize: CGFloat = 22
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
                    spectrum(barCount: 5, barWidth: 2.6, barHeight: 12, barSpacing: 2)
                }
                .padding(.leading, Layout.sharedLeadingInset)
                .frame(width: IslandShapeMetrics.musicNetworkEarWidth, alignment: .leading)
            } else {
                earArtwork
            }

            Spacer(minLength: 0)

            if let networkModel {
                CompactNetworkStackView(model: networkModel, earWidth: IslandShapeMetrics.musicNetworkEarWidth)
            } else {
                spectrum(barCount: 5, barWidth: 4, barHeight: 14, barSpacing: 3, barCornerRadius: 1)
                    .frame(width: IslandShapeMetrics.earWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The ear sets the height; the taller square hangs from its top edge and is clipped to it.
    private var earArtwork: some View {
        Color.clear
            .frame(width: Layout.earArtworkWidth)
            .overlay(alignment: .top) {
                ArtworkFillView(url: viewModel.artworkURL, glyphSize: Layout.earPlaceholderGlyphSize,
                                glyphCenter: Layout.earPlaceholderGlyphCenter)
                    .frame(width: Layout.earArtworkWidth, height: Layout.earArtworkWidth)
                    .clipped()
                    .offset(y: -Layout.earArtworkRaise)
            }
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: Layout.earArtworkFadeStart),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
    }

    private var artwork: some View {
        NowPlayingArtworkView(url: viewModel.artworkURL, cornerRadius: 6, placeholderIconSize: 10)
            .frame(width: Layout.artworkSize, height: Layout.artworkSize)
    }

    private func spectrum(barCount: Int, barWidth: CGFloat, barHeight: CGFloat, barSpacing: CGFloat,
                          barCornerRadius: CGFloat? = nil) -> some View {
        MusicSpectrumView(
            isActive: viewModel.playbackState.isPlaying,
            seed: viewModel.spectrumSeed,
            progress: viewModel.spectrumProgress,
            tempoBPM: viewModel.spectrumTempoBPM,
            levels: viewModel.spectrumLevels,
            barCount: barCount,
            barWidth: barWidth,
            barHeight: barHeight,
            barSpacing: barSpacing,
            tint: IslandTheme.accent,
            barCornerRadius: barCornerRadius
        )
        .fixedSize()
    }
}
