#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class SpectrumAnalyzerTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func sine(_ frequency: Double, amplitude: Float = 0.5, count: Int = 2048) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    private func analyzer(bands: Int = 14) -> SpectrumAnalyzer {
        SpectrumAnalyzer(bandCount: bands, sampleRate: sampleRate)!
    }

    private func loudestBand(_ levels: [Float]) -> Int {
        levels.enumerated().max { $0.element < $1.element }!.offset
    }

    func testSilenceGivesZeroOnEveryBand() {
        let levels = analyzer().levels(for: [Float](repeating: 0, count: 2048))
        XCTAssertEqual(levels, [Float](repeating: 0, count: 14))
    }

    func testTooFewSamplesReadAsSilence() {
        XCTAssertEqual(analyzer().levels(for: sine(200, count: 512)), [Float](repeating: 0, count: 14))
    }

    func testLowToneLightsALowBandAndHighToneAHighBand() {
        let a = analyzer()
        let low = loudestBand(a.levels(for: sine(200)))
        let high = loudestBand(a.levels(for: sine(8_000)))
        XCTAssertLessThanOrEqual(low, 4)
        XCTAssertGreaterThanOrEqual(high, 11)
        XCTAssertLessThan(low, high)
    }

    func testLevelsStayWithinZeroToOne() {
        let levels = analyzer().levels(for: sine(1_000, amplitude: 1))
        XCTAssertTrue(levels.allSatisfy { (0...1).contains($0) })
        XCTAssertGreaterThan(levels.max()!, 0.5)
    }

    func testLouderSignalReadsHigher() {
        let a = analyzer()
        let quiet = a.levels(for: sine(1_000, amplitude: 0.02)).max()!
        let loud = a.levels(for: sine(1_000, amplitude: 0.5)).max()!
        XCTAssertGreaterThan(loud, quiet)
    }

    func testOnlyTheLatestWindowCounts() {
        let a = analyzer()
        let burst = sine(8_000, count: 1024) + [Float](repeating: 0, count: 1024)
        XCTAssertEqual(a.levels(for: burst), [Float](repeating: 0, count: 14))
    }

    func testBandCountIsConfigurable() {
        XCTAssertEqual(analyzer(bands: 5).levels(for: sine(500)).count, 5)
        XCTAssertNil(SpectrumAnalyzer(bandCount: 0))
    }
}

final class SpectrumSmootherTests: XCTestCase {
    func testRisesFasterThanItFalls() {
        var smoother = SpectrumSmoother(bandCount: 1)
        let up = smoother.update([1])[0]
        _ = smoother.update([1])
        let before = smoother.levels[0]
        let after = smoother.update([0])[0]
        XCTAssertGreaterThan(up, before - after)
        XCTAssertGreaterThan(after, 0)
    }

    func testConvergesAndResets() {
        var smoother = SpectrumSmoother(bandCount: 2)
        for _ in 0..<40 { _ = smoother.update([1, 0.5]) }
        XCTAssertEqual(smoother.levels[0], 1, accuracy: 0.001)
        XCTAssertEqual(smoother.levels[1], 0.5, accuracy: 0.001)
        smoother.reset()
        XCTAssertEqual(smoother.levels, [0, 0])
    }

    func testMismatchedBandCountIsIgnored() {
        var smoother = SpectrumSmoother(bandCount: 2)
        XCTAssertEqual(smoother.update([1, 1, 1]), [0, 0])
    }
}

final class MonoMixerTests: XCTestCase {
    func testInterleavedStereoIsAveraged() {
        let samples: [Float] = [1, 3, 2, 4]
        samples.withUnsafeBufferPointer {
            let mono = MonoMixer.mix([AudioBlock(samples: $0.baseAddress!, channels: 2, frames: 2)])
            XCTAssertEqual(mono, [2, 3])
        }
    }

    func testOneBlockPerChannelIsAveraged() {
        let left: [Float] = [1, 1, 1]
        let right: [Float] = [3, 5, 7]
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                let mono = MonoMixer.mix([AudioBlock(samples: l.baseAddress!, channels: 1, frames: 3),
                                          AudioBlock(samples: r.baseAddress!, channels: 1, frames: 3)])
                XCTAssertEqual(mono, [2, 3, 4])
            }
        }
    }

    func testNoBlocksOrNoFramesGiveNothing() {
        XCTAssertEqual(MonoMixer.mix([]), [])
        let samples: [Float] = [1]
        samples.withUnsafeBufferPointer {
            XCTAssertEqual(MonoMixer.mix([AudioBlock(samples: $0.baseAddress!, channels: 1, frames: 0)]), [])
        }
    }

    func testRMS() {
        XCTAssertEqual(MonoMixer.rms([]), 0)
        XCTAssertEqual(MonoMixer.rms([0, 0]), 0)
        XCTAssertEqual(MonoMixer.rms([0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 0.0001)
    }
}

final class TapSilenceMonitorTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testWaitsThenDeclaresSilenceAfterThePatienceWindow() {
        var monitor = TapSilenceMonitor(startedAt: t0)
        monitor.record(rms: 0)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(1)), .waiting)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(TapSilenceMonitor.patience)), .silent)
    }

    func testAudioHeardInTimeSettlesItForGood() {
        var monitor = TapSilenceMonitor(startedAt: t0)
        monitor.record(rms: 0.05)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(1)), .heardAudio)
        // A quiet passage later is not a failure.
        monitor.record(rms: 0)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(60)), .heardAudio)
    }

    func testNoiseFloorDoesNotCountAsAudio() {
        var monitor = TapSilenceMonitor(startedAt: t0)
        monitor.record(rms: TapSilenceMonitor.audibleRMS / 2)
        XCTAssertEqual(monitor.verdict(at: t0.addingTimeInterval(10)), .silent)
    }
}

final class SpectrumLevelsTests: XCTestCase {
    func testShrinkingAveragesNeighbours() {
        XCTAssertEqual(SpectrumLevels.resample([0, 1, 0.5, 0.5], to: 2), [0.5, 0.5])
        XCTAssertEqual(SpectrumLevels.resample([1, 0, 0, 0, 0, 0], to: 3), [0.5, 0, 0])
    }

    func testGrowingRepeatsBands() {
        XCTAssertEqual(SpectrumLevels.resample([0.2, 0.8], to: 4), [0.2, 0.2, 0.8, 0.8])
    }

    func testSameCountIsIdentityAndEmptyIsEmpty() {
        XCTAssertEqual(SpectrumLevels.resample([0.1, 0.2, 0.3], to: 3), [0.1, 0.2, 0.3])
        XCTAssertEqual(SpectrumLevels.resample([], to: 5), [])
        XCTAssertEqual(SpectrumLevels.resample([1], to: 0), [])
    }
}
#endif
