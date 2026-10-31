import Accelerate
import Foundation

/// A block of audio as the tap delivers it: float samples with `channels` interleaved per frame.
struct AudioBlock {
    let samples: UnsafePointer<Float>
    let channels: Int
    let frames: Int
}

enum MonoMixer {
    /// The average of every channel of every block at each frame. Covers interleaved stereo in one block as well
    /// as one block per channel.
    static func mix(_ blocks: [AudioBlock]) -> [Float] {
        guard let frames = blocks.map(\.frames).min(), frames > 0 else { return [] }
        let channelCount = blocks.reduce(0) { $0 + $1.channels }
        guard channelCount > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for block in blocks where block.channels > 0 {
            for frame in 0..<frames {
                for channel in 0..<block.channels {
                    mono[frame] += block.samples[frame * block.channels + channel]
                }
            }
        }
        let scale = 1 / Float(channelCount)
        return mono.map { $0 * scale }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
        return value
    }
}

/// Turns mono audio into one 0...1 level per log-spaced frequency band (Hann window, FFT, decibel scale).
final class SpectrumAnalyzer {
    static let fftSize = 1024
    static let minFrequency = 60.0
    static let maxFrequency = 12_000.0
    /// Levels map -66...-6 dBFS onto 0...1; a full-scale sine reads about 1. Tuned by ear on real music.
    static let floorDecibels: Float = -66
    static let rangeDecibels: Float = 60
    /// Music loses energy toward the treble; this tilt keeps the right-hand bars from sitting flat.
    static let tiltDecibelsPerOctave: Float = 3

    let bandCount: Int
    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private let window: [Float]
    private let bandBins: [Range<Int>]
    private let bandTilt: [Float]
    private var windowed = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imaginary = [Float](repeating: 0, count: fftSize / 2)

    init?(bandCount: Int = 14, sampleRate: Double = 48_000) {
        guard bandCount > 0, sampleRate > 0, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.bandCount = bandCount
        self.setup = setup
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        window = hann

        let binHz = sampleRate / Double(Self.fftSize)
        let ratio = Self.maxFrequency / Self.minFrequency
        let edges = (0...bandCount).map { Self.minFrequency * pow(ratio, Double($0) / Double(bandCount)) }
        var ranges: [Range<Int>] = []
        var tilt: [Float] = []
        var previousHigh = max(1, Int(edges[0] / binHz))
        let lastBin = Self.fftSize / 2
        for band in 0..<bandCount {
            let low = min(previousHigh, lastBin - 1)
            let high = min(max(low + 1, Int(edges[band + 1] / binHz)), lastBin)
            ranges.append(low..<high)
            previousHigh = high
            let center = (edges[band] * edges[band + 1]).squareRoot()
            tilt.append(Self.tiltDecibelsPerOctave * Float(log2(center / 500)))
        }
        bandBins = ranges
        bandTilt = tilt
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Levels for the most recent `fftSize` samples; fewer samples than that read as silence.
    func levels(for samples: [Float]) -> [Float] {
        guard samples.count >= Self.fftSize else { return [Float](repeating: 0, count: bandCount) }
        samples.withUnsafeBufferPointer { buffer in
            let latest = buffer.baseAddress! + (samples.count - Self.fftSize)
            vDSP_vmul(latest, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        let scale = 1 / Float(Self.fftSize)
        return bandBins.enumerated().map { band, bins in
            var sum: Float = 0
            for bin in bins {
                sum += (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]).squareRoot() * scale
            }
            let mean = sum / Float(bins.count)
            let decibels = 20 * log10(max(mean, 1e-9)) + bandTilt[band]
            return min(max((decibels - Self.floorDecibels) / Self.rangeDecibels, 0), 1)
        }
    }
}

/// Fast attack, slow decay, so bars jump on a hit and fall away smoothly.
struct SpectrumSmoother {
    var attack: Float = 0.75
    var decay: Float = 0.2
    private(set) var levels: [Float]

    init(bandCount: Int) {
        levels = [Float](repeating: 0, count: bandCount)
    }

    mutating func update(_ target: [Float]) -> [Float] {
        guard target.count == levels.count else { return levels }
        for index in levels.indices {
            let rate = target[index] > levels[index] ? attack : decay
            levels[index] += (target[index] - levels[index]) * rate
        }
        return levels
    }

    mutating func reset() {
        levels = [Float](repeating: 0, count: levels.count)
    }
}

/// Decides whether a freshly started tap is hearing anything. Only the start is judged: once sound has arrived, a
/// quiet passage in the track is not a failure.
struct TapSilenceMonitor {
    enum Verdict: Equatable { case waiting, heardAudio, silent }

    static let audibleRMS: Float = 0.0003
    static let patience: TimeInterval = 4

    private let startedAt: Date
    private(set) var hasHeardAudio = false

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    mutating func record(rms: Float) {
        if rms > Self.audibleRMS { hasHeardAudio = true }
    }

    func verdict(at now: Date) -> Verdict {
        if hasHeardAudio { return .heardAudio }
        return now.timeIntervalSince(startedAt) >= Self.patience ? .silent : .waiting
    }
}
