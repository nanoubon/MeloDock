import SwiftUI

/// Expanded timer page: one countdown and one stopwatch side by side.
struct TimerView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 14
        static let stopwatchWidth: CGFloat = 190
        static let rowGap: CGFloat = 10
        static let progressHeight: CGFloat = 4
    }

    @ObservedObject var model: TimerModel
    @State private var customMinutes = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 0) {
                countdownColumn(now: context.date)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(IslandTheme.railTrack)
                    .frame(width: 1)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                stopwatchColumn(now: context.date)
                    .frame(width: Layout.stopwatchWidth, alignment: .leading)
                    .padding(.leading, 20)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(IslandTheme.textPrimary)
        }
    }

    // MARK: Countdown

    @ViewBuilder
    private func countdownColumn(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Layout.rowGap) {
            header("Timer", systemImage: "timer")
            switch model.countdown {
            case .idle:
                idleCountdown
            case .running:
                runningCountdown(now: now, paused: false)
            case .paused:
                runningCountdown(now: now, paused: true)
            case .finished:
                finishedCountdown
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 20)
    }

    private var idleCountdown: some View {
        VStack(alignment: .leading, spacing: Layout.rowGap) {
            HStack(spacing: 8) {
                ForEach(TimerInput.presetMinutes, id: \.self) { minutes in
                    Button("\(minutes) min") { model.startCountdown(duration: TimeInterval(minutes * 60)) }
                        .buttonStyle(IslandChipButtonStyle())
                        .accessibilityLabel("Start \(minutes) minute timer")
                }
            }
            HStack(spacing: 8) {
                TextField("Minutes", text: $customMinutes)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: 72, height: 28)
                    .background(Capsule(style: .continuous).fill(IslandTheme.chipFill))
                    .onSubmit(startCustom)
                    .accessibilityLabel("Custom timer minutes")
                Button("Start", action: startCustom)
                    .buttonStyle(IslandChipButtonStyle(prominent: true))
                    .disabled(TimerInput.duration(fromMinutes: customMinutes) == nil)
                    .accessibilityLabel("Start custom timer")
            }
        }
    }

    private func startCustom() {
        guard let duration = TimerInput.duration(fromMinutes: customMinutes) else { return }
        model.startCountdown(duration: duration)
        customMinutes = ""
    }

    private func runningCountdown(now: Date, paused: Bool) -> some View {
        let remaining = model.remaining(now: now)
        let fraction = model.countdownDuration > 0 ? 1 - remaining / model.countdownDuration : 0
        return VStack(alignment: .leading, spacing: Layout.rowGap) {
            Text(IslandTimeFormat.clock(remaining.rounded(.up)))
                .font(.system(size: 36, weight: .semibold).monospacedDigit())
                .opacity(paused ? 0.6 : 1)
                .accessibilityLabel("\(IslandTimeFormat.clock(remaining.rounded(.up))) remaining" + (paused ? ", paused" : ""))
            ProgressBar(fraction: fraction)
                .frame(height: Layout.progressHeight)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                if paused {
                    Button { model.resumeCountdown() } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(IslandChipButtonStyle(prominent: true))
                        .accessibilityLabel("Resume timer")
                } else {
                    Button { model.pauseCountdown() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(IslandChipButtonStyle(prominent: true))
                        .accessibilityLabel("Pause timer")
                }
                Button { model.cancelCountdown() } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(IslandChipButtonStyle())
                    .accessibilityLabel("Cancel timer")
            }
        }
    }

    private var finishedCountdown: some View {
        VStack(alignment: .leading, spacing: Layout.rowGap) {
            Text("Time's up")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.yellow)
            Button { model.dismissFinished() } label: { Label("Dismiss", systemImage: "bell.slash.fill") }
                .buttonStyle(IslandChipButtonStyle(prominent: true))
                .accessibilityLabel("Dismiss finished timer")
        }
    }

    // MARK: Stopwatch

    private func stopwatchColumn(now: Date) -> some View {
        let elapsed = model.stopwatchElapsed(now: now)
        let isRunning: Bool = { if case .running = model.stopwatch { return true } else { return false } }()
        let isIdle: Bool = { if case .idle = model.stopwatch { return true } else { return false } }()
        return VStack(alignment: .leading, spacing: Layout.rowGap) {
            header("Stopwatch", systemImage: "stopwatch")
            Text(IslandTimeFormat.clock(elapsed))
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .accessibilityLabel("Stopwatch \(IslandTimeFormat.clock(elapsed))")
            HStack(spacing: 8) {
                if isRunning {
                    Button { model.pauseStopwatch() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(IslandChipButtonStyle(prominent: true))
                        .accessibilityLabel("Pause stopwatch")
                } else {
                    Button { model.startStopwatch() } label: {
                        Label(isIdle ? "Start" : "Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(IslandChipButtonStyle(prominent: true))
                    .accessibilityLabel(isIdle ? "Start stopwatch" : "Resume stopwatch")
                }
                Button { model.resetStopwatch() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(IslandChipButtonStyle())
                    .disabled(isIdle)
                    .accessibilityLabel("Reset stopwatch")
            }
            Spacer(minLength: 0)
        }
    }

    private func header(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(IslandTheme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandTheme.railTrack)
                Capsule().fill(IslandTheme.progressFill)
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
    }
}
