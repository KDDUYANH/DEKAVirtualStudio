import XCTest
import Metal
import simd
@testable import DEKAVirtualStudio

/// Runs the production Metal kernels (simulator on Apple silicon, or a device).
final class MetalPipelineTests: XCTestCase {
    var harness: GPUTestHarness!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        harness = GPUTestHarness(context: try MetalContext())
    }

    func testAllPipelinesCompile() throws {
        // MetalContext init compiles every kernel; reaching here means the library is valid.
        XCTAssertNotNil(harness.context.prepareForeground)
        XCTAssertNotNil(harness.context.preview)
    }

    func testDecodeRoundTrip() throws {
        let r = try harness.checkDecode()
        XCTAssertTrue(r.pass, r.detail)
    }

    func testNeutralGradeIsIdentity() throws {
        var u = harness.neutralUniforms()
        u.colorEnabled = 1                        // enabled but every control at neutral
        let p = SIMD3<Float>(0.62, 0.41, 0.27)
        let off = try harness.runPrepare(rgb: p, uniforms: harness.neutralUniforms())
        let on = try harness.runPrepare(rgb: p, uniforms: u)
        XCTAssertLessThan(simd_reduce_max(simd_abs(on.rgb - off.rgb)), 0.004)
    }

    func testExposureOneStopDoublesLinearLight() throws {
        var u = harness.neutralUniforms()
        u.colorEnabled = 1
        u.exposure = 1
        let base = try harness.runPrepare(rgb: SIMD3(0.3, 0.3, 0.3), uniforms: harness.neutralUniforms())
        let up = try harness.runPrepare(rgb: SIMD3(0.3, 0.3, 0.3), uniforms: u)
        XCTAssertEqual(pow(up.rgb.x, 2.4) / pow(base.rgb.x, 2.4), 2, accuracy: 0.05)
    }

    func testLUT33MatchesCPUReference() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "DEKA_TealOrange_33", withExtension: "cube"))
        let r = try harness.checkLUT(CubeLUTParser.parse(data: Data(contentsOf: url)))
        XCTAssertTrue(r.pass, r.detail)
    }

    func testLUT65UploadsAndMatches() throws {
        var lut = CubeLUT.identity(size: 65)
        lut.values = lut.values.map { SIMD3($0.z, $0.x, $0.y) }          // channel swap: strongly non-identity
        let r = try harness.checkLUT(lut)
        XCTAssertTrue(r.pass, r.detail)
    }

    func testChromaKeyMatte() throws {
        let r = try harness.checkChroma()
        XCTAssertTrue(r.pass, r.detail)
    }

    func testNV12OutputLevels() throws {
        let r = try harness.checkNV12()
        XCTAssertTrue(r.pass, r.detail)
    }
}
