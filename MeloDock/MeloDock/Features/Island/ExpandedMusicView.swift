import SwiftUI

/// The expanded now-playing player: album artwork bleeding in from the leading edge behind a bold text column.
/// The island shell supplies its frame, background and clip.
struct ExpandedMusicView: View {
    /// Leading edge of the text column, beside the artwork. The tab strip lines up with it on every page.
    static let textLeading: CGFloat = Layout.artworkWidth

    private enum Layout {
        /// Width of the artwork layer; the text column (and the tab strip under it) starts here.
        static let artworkWidth: CGFloat = 236
        static let trailingPadding: CGFloat = 24
        /// Space between the notch (or the top of the shape) and the eyebrow row.
        static let topPadding: CGFloat = 8
        static let eyebrowHeight: CGFloat = 18
        /// Minimum gap between the label and the links; the links' own 6pt padding adds to it visually.
        static let eyebrowGap: CGFloat = 4
        static let eyebrowLabelGap: CGFloat = 7
        /// The links' 6pt inner padding hangs past the column so their text lines up with its trailing edge.
        static let linksTrailingOverhang: CGFloat = 6
        /// Device name cap (title plus chevron) used only when nothing else makes the eyebrow row fit.
        static let cappedOutputTitleWidth: CGFloat = 96
        static let titleTop: CGFloat = 6
        static let titleLineHeight: CGFloat = 36
        static let artistLineHeight: CGFloat = 20
        static let progressTop: CGFloat = 12
        static let progressHeight: CGFloat = 16
        static let progressGap: CGFloat = 10
        static let transportTop: CGFloat = 6
        static let transportHeight: CGFloat = 52
        static let volumeWidth: CGFloat = 128
        static let volumeGap: CGFloat = 8
        static let volumeHitHeight: CGFloat = 28

        /// The artwork is a square at least this big, trailing-aligned to the layer and raised a little.
        static let artworkMinSide: CGFloat = 262
        static let artworkRaise: CGFloat = 4
        /// Horizontal fade: opaque up to this fraction of the layer, clear at its trailing edge.
        static let artworkFadeStart: CGFloat = 0.52
        /// Vertical fade from the top of the shape: clear down to `artworkTopClear`, opaque from `artworkTopOpaque`.
        static let artworkTopClear: CGFloat = 18
        static let artworkTopOpaque: CGFloat = 64
        /// Placeholder glyph center in layer coordinates (x), inside the opaque part of the fade.
        static let placeholderGlyphX: CGFloat = 96
        static let placeholderGlyphSize: CGFloat = 44
    }

    private enum Motion {
        static let firstGroupDelay: Double = 0.05
        static let groupStagger: Double = 0.04
        static let reveal = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let reducedReveal = Animation.easeInOut(duration: 0.15)
    }

    @ObservedObject var viewModel: IslandViewModel
    /// Height of the physical notch above the page. The artwork reaches up through it to the top of the shape.
    var topInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    /// Playback controls are dimmed while the provider still needs authorization.
    private var playbackOpacity: Double {
        viewModel.authState == .authorized ? 1 : IslandTheme.dimmedOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(identityBlock, group: 0)
            reveal(progressRow, group: 1)
                .padding(.top, Layout.progressTop)
            reveal(transportRow, group: 2)
                .padding(.top, Layout.transportTop)
        }
        .padding(.leading, Layout.artworkWidth)
        .padding(.trailing, Layout.trailingPadding)
        .padding(.top, Layout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .topLeading) { artworkLayer }
        .foregroundStyle(IslandTheme.textPrimary)
        .onAppear { isRevealed = true }
    }

    // MARK: - Artwork

    /// The artwork spans the whole expanded shape: up through the notch and down behind the tab strip, which is
    /// drawn after the page and so sits on top. It fades out toward the text column and toward the top edge.
    private var artworkLayer: some View {
        let height = topInset + IslandShapeMetrics.expandedSize.height
        let side = max(Layout.artworkMinSide, height + Layout.artworkRaise)
        let origin = CGPoint(x: Layout.artworkWidth - side, y: -Layout.artworkRaise)
        let glyphCenter = UnitPoint(
            x: (Layout.placeholderGlyphX - origin.x) / side,
            y: ((Layout.artworkTopOpaque + height) / 2 - origin.y) / side
        )

        return ArtworkFillView(url: viewModel.artworkURL, glyphSize: Layout.placeholderGlyphSize,
                               glyphCenter: glyphCenter)
            .frame(width: side, height: side)
            .clipped()
            .offset(x: origin.x, y: origin.y)
            .frame(width: Layout.artworkWidth, height: height, alignment: .topLeading)
            .clipped()
            .mask(artworkMask(height: height))
            .offset(y: -topInset)
            .opacity(isRevealed ? 1 : 0)
            .animation(revealAnimation(group: 0), value: isRevealed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Two fades intersected: horizontal (opaque, then clear at the trailing edge) and vertical (clear at the top).
    private func artworkMask(height: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: Layout.artworkFadeStart),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: Layout.artworkTopClear / height),
                    .init(color: .black, location: Layout.artworkTopOpaque / height),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Rows

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
                .frame(height: Layout.eyebrowHeight)

            Text(viewModel.trackTitle)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Layout.titleLineHeight)
                .padding(.top, Layout.titleTop)

            Text(viewModel.trackArtist)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IslandTheme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Layout.artistLineHeight)
        }
    }

    /// "Now Playing" with a small spectrum on the leading side; Connect, source and output links on the trailing side.
    /// Takes the first arrangement that fits: everything; then without the label; then also capping the device name.
    private var eyebrowRow: some View {
        ViewThatFits(in: .horizontal) {
            eyebrowContent(showsLabel: true, outputTitleWidth: nil)
            eyebrowContent(showsLabel: false, outputTitleWidth: nil)
            eyebrowContent(showsLabel: false, outputTitleWidth: Layout.cappedOutputTitleWidth)
        }
    }

    private func eyebrowContent(showsLabel: Bool, outputTitleWidth: CGFloat?) -> some View {
        HStack(spacing: Layout.eyebrowGap) {
            HStack(spacing: Layout.eyebrowLabelGap) {
                if viewModel.shouldShowSpectrum {
                    eyebrowSpectrum
                }
                if showsLabel, let eyebrowLabel {
                    Text(eyebrowLabel)
                        .font(.system(size: 10.5, weight: .heavy))
                        .tracking(1.26)
                        .textCase(.uppercase)
                        .foregroundStyle(IslandTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                if viewModel.authState != .authorized {
                    Button("Connect") {
                        viewModel.authorizeCurrentProvider()
                    }
                    .buttonStyle(IslandLinkButtonStyle(accent: true))
                    .focusEffectDisabled()
                    .fixedSize()
                }

                SourceChip(selection: viewModel.selectedProvider) { viewModel.setProvider($0) }

                OutputChip(
                    outputs: viewModel.outputs,
                    selectedID: viewModel.selectedOutputID,
                    maxTitleWidth: outputTitleWidth,
                    onSelect: { viewModel.chooseOutput($0) }
                )
            }
            .fixedSize()
            .padding(.trailing, -Layout.linksTrailingOverhang)
        }
    }

    /// "Now Playing" or "Paused" over a known track; nothing while there is no track, so it never repeats the
    /// "Nothing Playing" or "Now Playing" title fallbacks.
    private var eyebrowLabel: String? {
        if viewModel.playbackState.isPlaying { return "Now Playing" }
        return viewModel.playbackState.track == nil ? nil : "Paused"
    }

    private var eyebrowSpectrum: some View {
        MusicSpectrumView(
            isActive: viewModel.playbackState.isPlaying,
            seed: viewModel.spectrumSeed,
            progress: viewModel.spectrumProgress,
            tempoBPM: viewModel.spectrumTempoBPM,
            levels: viewModel.spectrumLevels,
            barCount: 4,
            barWidth: 3,
            barHeight: 11,
            barSpacing: 2,
            tint: IslandTheme.accent,
            barCornerRadius: 1
        )
        .fixedSize()
    }

    private var progressRow: some View {
        HStack(spacing: Layout.progressGap) {
            // The rail carries the spoken position; the times would only repeat it.
            Text(viewModel.elapsedTimeText)
                .foregroundStyle(IslandTheme.textPrimary)
                .fixedSize()
                .accessibilityHidden(true)

            ScrubRail(
                value: viewModel.progressFraction,
                fill: IslandTheme.accent,
                accessibilityLabel: "Playback position",
                accessibilityValue: progressAccessibilityValue,
                track: IslandTheme.progressTrack
            )
            .frame(height: Layout.progressHeight)

            Text(viewModel.durationTimeText)
                .foregroundStyle(IslandTheme.textMuted)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .font(.system(size: 12, weight: .bold))
        .monospacedDigit()
        .frame(height: Layout.progressHeight)
        // Unknown duration (e.g. streamed Apple Music tracks): hide the row but keep its layout space.
        .opacity(viewModel.hasKnownDuration ? playbackOpacity : 0)
        .accessibilityHidden(!viewModel.hasKnownDuration)
        .allowsHitTesting(viewModel.hasKnownDuration)
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            PlayerControlsView(
                isPlaying: viewModel.playbackState.isPlaying,
                onPrevious: { viewModel.playPrevious() },
                onPlayPause: { viewModel.togglePlayPause() },
                onNext: { viewModel.playNext() }
            )
            .opacity(playbackOpacity)

            Spacer(minLength: Layout.volumeGap)

            volumeCluster
                .frame(width: Layout.volumeWidth)
        }
        .frame(height: Layout.transportHeight)
    }

    private var volumeCluster: some View {
        HStack(spacing: Layout.volumeGap) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(IslandTheme.textSecondary)
                .accessibilityHidden(true)

            ScrubRail(
                value: Double(viewModel.volume),
                fill: .white,
                accessibilityLabel: "Volume",
                accessibilityValue: "\(Int((ScrubRailMath.clamped(Double(viewModel.volume)) * 100).rounded())) percent",
                onChange: { viewModel.setVolume(Float($0)) },
                growsWhenActive: false
            )
            .frame(height: Layout.volumeHitHeight)
        }
    }

    private var progressAccessibilityValue: String {
        let duration = viewModel.durationTimeText
        return duration == "--:--" ? viewModel.elapsedTimeText : "\(viewModel.elapsedTimeText) of \(duration)"
    }

    // MARK: - Reveal

    /// Fades a row in on appear; staggered with a small rise and scale unless Reduce Motion is on.
    private func reveal<Content: View>(_ content: Content, group: Int) -> some View {
        let settled = isRevealed || reduceMotion
        return content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: settled ? 0 : 8)
            .scaleEffect(settled ? 1 : 0.96, anchor: .top)
            .animation(revealAnimation(group: group), value: isRevealed)
    }

    private func revealAnimation(group: Int) -> Animation {
        if reduceMotion { return Motion.reducedReveal }
        return Motion.reveal.delay(Motion.firstGroupDelay + Motion.groupStagger * Double(group))
    }
}

/// Edge-to-edge album artwork for the expanded backdrop and the compact ear: the image scaled to fill, or a dark
/// gradient with a music-note glyph. Callers size, clip and mask it.
struct ArtworkFillView: View {
    let url: URL?
    let glyphSize: CGFloat
    /// Where the placeholder glyph sits, relative to the frame, so callers can keep it in the visible part.
    var glyphCenter: UnitPoint = .center

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color(white: 0.20), Color(white: 0.07)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                GeometryReader { geometry in
                    Image(systemName: "music.note")
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .position(x: geometry.size.width * glyphCenter.x, y: geometry.size.height * glyphCenter.y)
                }
            }
    }
}

/// Rounded album artwork with a music-note placeholder, used by the compact ear while it shares space with the network speed.
struct NowPlayingArtworkView: View {
    let url: URL?
    let cornerRadius: CGFloat
    let placeholderIconSize: CGFloat

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.11))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: placeholderIconSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1, antialiased: true)
            )
    }
}
