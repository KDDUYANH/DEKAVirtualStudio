import XCTest
import simd
import CoreVideo
@testable import DEKAVirtualStudio

final class ColorAndKeyTests: XCTestCase {

    func testWhiteBalanceKeepsLuminance() {
        for t in stride(from: Float(-1), through: 1, by: 0.5) {
            for m in stride(from: Float(-1), through: 1, by: 0.5) {
                let g = ColorEngine.whiteBalanceGains(temperature: t, tint: m)
                XCTAssertEqual(simd_dot(g, SIMD3(0.2126, 0.7152, 0.0722)), 1, accuracy: 1e-5)
            }
        }
        XCTAssertEqual(ColorEngine.whiteBalanceGains(temperature: 0, tint: 0), SIMD3(1, 1, 1))
        let warm = ColorEngine.whiteBalanceGains(temperature: 1, tint: 0)
        XCTAssertGreaterThan(warm.x, warm.z)
    }

    func testDecodeMatrices() {
        // Full-range BT.709: pure red has Cb = −0.1146, Cr = +0.5 (centered).
        let d = ColorEngine.decode(matrixName: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String, fullRange: true)
        let y: Float = 0.2126, cb: Float = (0 - 0.2126) / 1.8556, cr: Float = (1 - 0.2126) / 1.5748
        let rgb = d.matrix * SIMD3(y, cb, cr)
        XCTAssertEqual(rgb.x, 1, accuracy: 1e-4)
        XCTAssertEqual(rgb.y, 0, accuracy: 1e-4)
        XCTAssertEqual(rgb.z, 0, accuracy: 1e-4)
        // Video range offsets
        let v = ColorEngine.decode(matrixName: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String, fullRange: false)
        XCTAssertEqual(v.offset.x, 16.0 / 255.0, accuracy: 1e-6)
        XCTAssertEqual(v.scale.x, 255.0 / 219.0, accuracy: 1e-6)
    }

    func testKeyColourCbCrMatchesShaderFormula() {
        let g = ChromaKeyEngine.cbcr(of: .chromaGreen)
        XCTAssertLessThan(g.x, 0); XCTAssertLessThan(g.y, 0)     // green: both chroma negative
        let b = ChromaKeyEngine.cbcr(of: .chromaBlue)
        XCTAssertGreaterThan(b.x, 0)                               // blue: Cb positive
    }

    func testKeyerUniforms() {
        var u = DEKAFrameUniforms()
        ChromaKeyEngine.apply(mode: .greenScreen, chroma: ChromaSettings(), to: &u)
        XCTAssertEqual(u.keyMode, Int32(DEKA_KEY_CHROMA))
        ChromaKeyEngine.apply(mode: .aiCutout, chroma: ChromaSettings(), to: &u)
        XCTAssertEqual(u.keyMode, Int32(DEKA_KEY_AI))
    }

    func testUniformLayoutIsStable() {
        // Guards against accidental C/MSL layout drift (both sides compile ShaderTypes.h).
        XCTAssertEqual(MemoryLayout<DEKABlurParams>.stride, 8)
        XCTAssertEqual(MemoryLayout<DEKAFrameUniforms>.alignment, 16)
    }
}
