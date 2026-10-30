import SwiftUI

/// The expanded now-playing player. The island shell supplies its frame, background and clip.
struct ExpandedMusicView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 24
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 14
        static let rowGap: CGFloat = 10
        static let transportGap: CGFloat = 2
        static let artworkSize: CGFloat = 72
        static let artworkRadius: CGFloat = 16
        static let artworkToText: CGFloat = 16
        static let chipGap: CGFloat = 8
        static let titleLineHeight: CGFloat = 24
        static let artistLineHeight: CGFloat = 18
        static let railHitHeight: CGFloat = 14
        static let timesHeight: CGFloat = 14
        static let transportHeight: CGFloat = 44
        static let sideSlotWidth: CGFloat = 180
        static let volumeRailWidth: CGFloat = 112
        static let volumeHitHeight: CGFloat = 28
    }

    private enum Motion {
        static let firstGroupDelay: Double = 0.05
        static let groupStagger: Double = 0.04
        static let reveal = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let reducedReveal = Animation.easeInOut(duration: 0.15)
    }

    @ObservedObject var viewModel: IslandViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    /// Playback controls are dimmed while the provider still needs authorization.
    private var playbackOpacity: Double {
        viewModel.authState == .authorized ? 1 : IslandTheme.dimmedOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(identityRow, group: 0)
            reveal(progressSection, group: 1)
                .padding(.top, Layout.rowGap)
            reveal(transportRow, group: 2)
                .padding(.top, Layout.transportGap)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topPadding)
        .padding(.bottom, Layout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(IslandTheme.textPrimary)
        .onAppear { isRevealed = true }
    }

    // MARK: - Rows

    private var identityRow: some View {
        HStack(spacing: Layout.artworkToText) {
            NowPlayingArtworkView(url: viewModel.artworkURL, cornerRadius: Layout.artworkRadius, placeholderIconSize: 26)
                .frame(width: Layout.artworkSize, height: Layout.artworkSize)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.artworkRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.trackTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minHeight: Layout.titleLineHeight)
                    .layoutPriority(1)

                Text(viewModel.trackArtist)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(IslandTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minHeight: Layout.artistLineHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: Layout.chipGap) {
                    if viewModel.authState != .authorized {
                        Button("Connect") {
                            viewModel.authorizeCurrentProvider()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(IslandChipButtonStyle(prominent: true))
                        .focusEffectDisabled()
                        .fixedSize()
                    }

                    SourceChip(selection: viewModel.selectedProvider) { viewModel.setProvider($0) }
                }

                Spacer(minLength: 0)

                if viewModel.shouldShowSpectrum {
                    MusicSpectrumView(
                        isActive: viewModel.playbackState.isPlaying,
                        seed: viewModel.spectrumSeed,
                        progress: viewModel.spectrumProgress,
                        tempoBPM: viewModel.spectrumTempoBPM,
                        barCount: 5,
                        barWidth: 3,
                        barHeight: 16,
                        barSpacing: 2
                    )
                    .fixedSize()
                    .padding(.trailing, 4)
                }
            }
            .frame(height: Layout.artworkSize)
        }
        .frame(height: Layout.artworkSize)
    }

    private var progressSection: some View {
        VStack(spacing: 2) {
            ScrubRail(
                value: viewModel.progressFraction,
                fill: IslandTheme.progressFill,
                accessibilityLabel: "Playback position",
                accessibilityValue: progressAccessibilityValue
            )
            .frame(height: Layout.railHitHeight)

            HStack {
                Text(viewModel.elapsedTimeText)
                Spacer()
                Text(viewModel.durationTimeText)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(IslandTheme.textTertiary)
            .frame(height: Layout.timesHeight)
            .accessibilityHidden(true)
        }
        .opacity(playbackOpacity)
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            volumeCluster
                .frame(width: Layout.sideSlotWidth, alignment: .leading)

            PlayerControlsView(
                isPlaying: viewModel.playbackState.isPlaying,
                onPrevious: { viewModel.playPrevious() },
                onPlayPause: { viewModel.togglePlayPause() },
                onNext: { viewModel.playNext() }
            )
            .opacity(playbackOpacity)
            .frame(maxWidth: .infinity)

            OutputChip(
                outputs: viewModel.outputs,
                selectedID: viewModel.selectedOutputID,
                onSelect: { viewModel.chooseOutput($0) }
            )
            .frame(width: Layout.sideSlotWidth, alignment: .trailing)
        }
        .frame(height: Layout.transportHeight)
    }

    private var volumeCluster: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IslandTheme.textSecondary)
                .accessibilityHidden(true)

            ScrubRail(
                value: Double(viewModel.volume),
                fill: IslandTheme.volumeFill,
                accessibilityLabel: "Volume",
                accessibilityValue: "\(Int((ScrubRailMath.clamped(Double(viewModel.volume)) * 100).rounded())) percent",
                onChange: { viewModel.setVolume(Float($0)) }
            )
            .frame(width: Layout.volumeRailWidth, height: Layout.volumeHitHeight)
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

/// Album artwork with a music-note placeholder, shared by the compact and expanded views.
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
