import XCTest
@testable import DEKAVirtualStudio

final class SceneEngineTests: XCTestCase {
    func testCutHasNoOutgoing() {
        let e = SceneEngine(scenes: SceneModel.defaultScenes(), activeID: nil)
        let target = e.scenes[1].id
        e.take(target, transition: .cut, duration: 0.5, now: 10)
        let s = e.renderState(at: 10)
        XCTAssertNil(s.outgoing)
        XCTAssertEqual(s.incoming.id, target)
        XCTAssertEqual(s.mix, 1)
    }

    func testFadeProgressAndCompletion() {
        let e = SceneEngine(scenes: SceneModel.defaultScenes(), activeID: nil)
        let first = e.activeSceneID
        let target = e.scenes[2].id
        e.take(target, transition: .fade, duration: 1, now: 100)
        let mid = e.renderState(at: 100.5)
        XCTAssertEqual(mid.outgoing?.id, first)
        XCTAssertEqual(mid.mix, 0.5, accuracy: 1e-5)          // smoothstep(0.5) = 0.5
        XCTAssertLessThan(e.renderState(at: 100.1).mix, 0.1)
        XCTAssertNil(e.renderState(at: 101.01).outgoing)
    }

    func testTakingActiveSceneIsNoOp() {
        let e = SceneEngine(scenes: SceneModel.defaultScenes(), activeID: nil)
        e.take(e.activeSceneID, transition: .fade, duration: 1, now: 0)
        XCTAssertNil(e.renderState(at: 0.5).outgoing)
    }

    func testRemoveKeepsAtLeastOneScene() {
        let e = SceneEngine(scenes: [SceneModel(name: "Only")], activeID: nil)
        e.removeScene(e.activeSceneID)
        XCTAssertEqual(e.scenes.count, 1)
    }
}

final class ThermalPolicyTests: XCTestCase {
    let ctx = ThermalContext(outputFPS: 60, aiActive: true, aiFPS: 30, chromaFallbackAllowed: true, applied: [])

    func testNominalDoesNothing() {
        XCTAssertEqual(ThermalPolicy().actions(level: .nominal, context: ctx), [])
    }

    func testFairOnlyWarns() {
        let a = ThermalPolicy().actions(level: .fair, context: ctx)
        XCTAssertEqual(a.count, 1)
        if case .warn = a[0] {} else { XCTFail() }
    }

    func testSeriousAppliesOneStepInOrder() {
        let a = ThermalPolicy().actions(level: .serious, context: ctx)
        XCTAssertTrue(a.contains(.apply(.reduceAIRate)))
        XCTAssertFalse(a.contains(.apply(.reduceFrameRate)))
        var c = ctx; c.applied = [.reduceAIRate]; c.aiFPS = 15
        XCTAssertTrue(ThermalPolicy().actions(level: .serious, context: c).contains(.apply(.reduceFrameRate)))
    }

    func testCriticalAppliesAllRemaining() {
        let a = ThermalPolicy().actions(level: .critical, context: ctx)
        XCTAssertTrue(a.contains(.apply(.reduceAIRate)))
        XCTAssertTrue(a.contains(.apply(.reduceFrameRate)))
        XCTAssertTrue(a.contains(.apply(.aiToChroma)))
    }

    func testRespectsConfiguration() {
        var c = ctx; c.chromaFallbackAllowed = false; c.outputFPS = 30
        let a = ThermalPolicy().actions(level: .critical, context: c)
        XCTAssertFalse(a.contains(.apply(.aiToChroma)))
        XCTAssertFalse(a.contains(.apply(.reduceFrameRate)))
    }
}

final class CaptureAndPresetTests: XCTestCase {
    private func cand(_ i: Int, _ w: Int32, _ h: Int32, _ fps: Double, full: Bool = true, binned: Bool = false) -> FormatCandidate {
        FormatCandidate(index: i, width: w, height: h, maxFPS: fps, fullRange: full, isBinned: binned, isVideoHDR: false)
    }

    func testSelectorPrefersFullRangeAndBinned() {
        let c = [cand(0, 1920, 1080, 60, full: false), cand(1, 1920, 1080, 60), cand(2, 1920, 1080, 60, binned: true)]
        XCTAssertEqual(CameraFormatSelector.select(from: c, resolution: .hd1080, fps: 60)?.index, 2)
        XCTAssertNil(CameraFormatSelector.select(from: c, resolution: .uhd4k, fps: 30))
    }

    func testSupportedModesNeverIncludeUnsupported() {
        let c = [cand(0, 1920, 1080, 30), cand(1, 1280, 720, 60)]
        let modes = CameraFormatSelector.supportedModes(from: c)
        XCTAssertTrue(modes.contains(CaptureMode(resolution: .hd1080, fps: 30)))
        XCTAssertFalse(modes.contains(CaptureMode(resolution: .hd1080, fps: 60)))
        XCTAssertTrue(modes.contains(CaptureMode(resolution: .hd720, fps: 60)))
    }

    func testPresetFallsBackWithReason() {
        let supported = [CaptureMode(resolution: .hd1080, fps: 30), CaptureMode(resolution: .hd720, fps: 30)]
        let r = QualityPreset.resolve(.broadcast, supported: supported)
        XCTAssertEqual(r.mode, CaptureMode(resolution: .hd1080, fps: 30))
        XCTAssertNotNil(r.note)
        XCTAssertNil(QualityPreset.resolve(.mobile, supported: supported).note)
    }
}

final class StreamMathTests: XCTestCase {
    func testBitrateFromCounters() {
        // 750 000 bytes in 1000 ms = 6000 kbps
        XCTAssertEqual(StatsMath.kbps(bytesNow: 1_750_000, bytesBefore: 1_000_000, msNow: 2000, msBefore: 1000), 6000, accuracy: 0.001)
        XCTAssertEqual(StatsMath.kbps(bytesNow: 10, bytesBefore: 20, msNow: 2, msBefore: 1), 0)   // counter reset
        XCTAssertEqual(StatsMath.fps(framesNow: 160, framesBefore: 100, msNow: 2000, msBefore: 1000), 60, accuracy: 1e-9)
    }

    func testReconnectBackoff() {
        let p = ReconnectPolicy(baseDelay: 1, maxDelay: 15, maxAttempts: 5)
        XCTAssertEqual(p.delay(forAttempt: 1, random: 0.5)!, 1, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 3, random: 0.5)!, 4, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 5, random: 0.5)!, 15, accuracy: 1e-9)   // capped
        XCTAssertNil(p.delay(forAttempt: 6))
        XCTAssertEqual(p.delay(forAttempt: 2, random: 0)!, 1.5, accuracy: 1e-9)      // −25 % jitter
    }

    func testStreamStateLabels() {
        XCTAssertEqual(StreamState.off.label, "STREAM OFF")
        XCTAssertTrue(StreamState.reconnecting(attempt: 2).isOnAir)
        XCTAssertFalse(StreamState.connecting.isOnAir)
    }
}

final class GraphicsMathTests: XCTestCase {
    func testCountdownFormatting() {
        XCTAssertEqual(GraphicsEngine.countdownString(remaining: 65), "01:05")
        XCTAssertEqual(GraphicsEngine.countdownString(remaining: 3601), "1:00:01")
        XCTAssertEqual(GraphicsEngine.countdownString(remaining: -5), "00:00")
    }

    func testTickerScrollWraps() {
        let size = CGSize(width: 1920, height: 1080)
        let s0 = GraphicsEngine.tickerScroll(time: 0, speed: 0.1, outputSize: size, stripAspect: 20)
        XCTAssertEqual(s0, 0)
        let s = GraphicsEngine.tickerScroll(time: 1000, speed: 0.1, outputSize: size, stripAspect: 20)
        XCTAssertGreaterThanOrEqual(s, 0); XCTAssertLessThan(s, 1)
    }
}

final class SRTConfigurationTests: XCTestCase {
    func testSRTPublishURLGeneration() {
        var output = OutputSettings()
        output.srtHost = "192.168.1.50"
        output.srtPort = 9000
        output.srtStreamId = "publish:cam1"
        output.srtLatencyMs = 200
        output.srtPassphrase = "secretPassphrase"

        let url = output.srtPublishURLString
        XCTAssertEqual(url, "srt://192.168.1.50:9000?mode=caller&latency=200&streamid=publish:cam1&passphrase=secretPassphrase")
        XCTAssertEqual(output.srtPublishURL, url)
    }

    func testSRTReturnURLGeneration() {
        var output = OutputSettings()
        output.srtHost = "192.168.1.50"
        output.srtReturnHost = "192.168.1.55"
        output.srtReturnPort = 9000
        output.srtReturnStreamId = "read:program"
        output.srtLatencyMs = 150
        output.srtReturnEnabled = true

        let url = output.srtReturnURLString
        XCTAssertEqual(url, "srt://192.168.1.55:9000?mode=caller&latency=150&streamid=read:program")
        XCTAssertEqual(output.srtReturnURL, url)
    }
}
