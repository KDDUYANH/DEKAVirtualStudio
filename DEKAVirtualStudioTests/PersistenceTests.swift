import XCTest
import CoreMedia
@testable import DEKAVirtualStudio

final class ProjectManagerTests: XCTestCase {
    var dir: URL!
    var pm: ProjectManager!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        pm = ProjectManager(root: dir)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testSaveLoadRoundTrip() throws {
        var p = try pm.create(name: "Studio A")
        p.scenes[0].color.exposure = 0.7
        var secondScene = SceneModel(name: "Scene 2")
        secondScene.keyMode = .greenScreen
        p.scenes.append(secondScene)
        p.output.streamName = "deka-test"
        p.output.srtHost = "10.0.0.1"
        p.output.srtPort = 9000
        p.output.srtStreamId = "publish:test"
        p.output.srtReturnEnabled = true
        p.output.srtReturnStreamId = "read:test"
        p.output.cleanFeedLiveOutput = true
        try pm.save(p)
        let loaded = try pm.load(id: p.id)
        XCTAssertEqual(loaded.scenes[0].color.exposure, 0.7)
        XCTAssertEqual(loaded.scenes[1].keyMode, .greenScreen)
        XCTAssertEqual(loaded.output.streamName, "deka-test")
        XCTAssertEqual(loaded.output.srtHost, "10.0.0.1")
        XCTAssertEqual(loaded.output.srtPort, 9000)
        XCTAssertEqual(loaded.output.srtStreamId, "publish:test")
        XCTAssertEqual(loaded.output.srtReturnEnabled, true)
        XCTAssertEqual(loaded.output.srtReturnStreamId, "read:test")
        XCTAssertEqual(loaded.output.cleanFeedLiveOutput, true)
        XCTAssertEqual(pm.list().count, 1)
    }

    func testOlderFilesMissingKeysStillLoad() throws {
        // A minimal file as an older version might have written it.
        let json = """
        {"name":"Legacy","id":"\(UUID().uuidString)","scenes":[{"name":"Only","id":"\(UUID().uuidString)","color":{"exposure":1.5}}]}
        """
        let p = try ProjectManager.decodeProject(from: Data(json.utf8))
        XCTAssertEqual(p.name, "Legacy")
        XCTAssertEqual(p.scenes.count, 1)
        XCTAssertEqual(p.scenes[0].color.exposure, 1.5)
        XCTAssertEqual(p.scenes[0].color.contrast, 0)          // default filled in
        XCTAssertEqual(p.output.fps, 30)
    }

    func testDuplicateGetsNewIdentity() throws {
        let p = try pm.create(name: "A")
        let d = try pm.duplicate(id: p.id)
        XCTAssertNotEqual(d.id, p.id)
        XCTAssertEqual(d.name, "A Copy")
    }
}

final class KeychainTests: XCTestCase {
    func testSetGetDelete() throws {
        let k = KeychainStore(service: "vn.kdproductions.deka.tests.\(UUID().uuidString)")
        try k.setString("secret", for: "a")
        XCTAssertEqual(k.string(for: "a"), "secret")
        try k.setString("rotated", for: "a")                    // update path
        XCTAssertEqual(k.string(for: "a"), "rotated")
        try k.delete("a")
        XCTAssertNil(k.string(for: "a"))
    }

    func testSessionTokenValidity() {
        let now = Date()
        XCTAssertTrue(SessionToken(token: "t", expiresAt: now.addingTimeInterval(3600)).isValid(now: now))
        XCTAssertFalse(SessionToken(token: "t", expiresAt: now.addingTimeInterval(60)).isValid(now: now))   // inside 5-min margin
    }
}

final class AudioBufferTests: XCTestCase {
    func testChunkToSampleBuffer() throws {
        let chunk = AudioChunk(samples: [Int16](repeating: 100, count: 960), channels: 2, sampleRate: 48_000,
                               frameCount: 480, presentationTime: CMTime(value: 1, timescale: 1))
        let sb = try XCTUnwrap(AudioSampleBufferFactory.makeSampleBuffer(chunk))
        XCTAssertEqual(CMSampleBufferGetNumSamples(sb), 480)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sb), CMTime(value: 1, timescale: 1))
    }
}
