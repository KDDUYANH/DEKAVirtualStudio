import XCTest
import simd
@testable import DEKAVirtualStudio

final class CubeLUTParserTests: XCTestCase {

    private func cubeText(size n: Int, title: String = "T", transform: (SIMD3<Float>) -> SIMD3<Float> = { $0 }) -> String {
        var lines = ["# comment", "TITLE \"\(title)\"", "LUT_3D_SIZE \(n)", ""]
        let d = Float(n - 1)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let v = transform(SIMD3(Float(r) / d, Float(g) / d, Float(b) / d))
            lines.append(String(format: "%.6f %.6f %.6f", v.x, v.y, v.z))
        } } }
        return lines.joined(separator: "\r\n")
    }

    func testParsesStandardSizes() throws {
        for n in [17, 33, 65] {
            let lut = try CubeLUTParser.parse(text: cubeText(size: n, title: "S\(n)"))
            XCTAssertEqual(lut.size, n)
            XCTAssertEqual(lut.values.count, n * n * n)
            XCTAssertEqual(lut.title, "S\(n)")
        }
    }

    func testRedVariesFastest() throws {
        let lut = try CubeLUTParser.parse(text: cubeText(size: 3))
        XCTAssertEqual(lut.values[1], SIMD3(0.5, 0, 0))   // second entry = next red step
        XCTAssertEqual(lut.values[3], SIMD3(0, 0.5, 0))   // after one full red row, green steps
        XCTAssertEqual(lut.values[9], SIMD3(0, 0, 0.5))
    }

    func testDomainKeywords() throws {
        let text = "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n" + (0..<8).map { _ in "0 0 0" }.joined(separator: "\n")
        let lut = try CubeLUTParser.parse(text: text)
        XCTAssertEqual(lut.domainMax, SIMD3(repeating: 2))
    }

    func testRejectsBadFiles() {
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "LUT_1D_SIZE 1024\n0 0 0")) { XCTAssertEqual($0 as? CubeLUTError, .unsupported1D) }
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "0 0 0\n1 1 1")) { XCTAssertEqual($0 as? CubeLUTError, .missingSize) }
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "LUT_3D_SIZE 2\n0 0 0")) {
            XCTAssertEqual($0 as? CubeLUTError, .wrongCount(expected: 8, found: 1))
        }
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "LUT_3D_SIZE 2\n0 0 zero")) { e in
            if case .badLine = e as? CubeLUTError {} else { XCTFail("expected badLine") }
        }
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "LUT_3D_SIZE 999"))
    }

    func testCPUReferenceTrilinearIsExactForLinearLUT() throws {
        // A LUT of an affine function is reproduced exactly by trilinear interpolation.
        let f: (SIMD3<Float>) -> SIMD3<Float> = { SIMD3($0.x * 0.8 + 0.1, $0.y * 0.5, 1 - $0.z) }
        let lut = try CubeLUTParser.parse(text: cubeText(size: 5, transform: f))
        for p in [SIMD3<Float>(0.13, 0.77, 0.41), SIMD3(0.99, 0.01, 0.5), SIMD3(0.5, 0.5, 0.5)] {
            XCTAssertLessThan(simd_reduce_max(simd_abs(lut.sample(p) - f(p))), 1e-4)
        }
    }

    func testBundledAcceptanceLUTParses() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "DEKA_TealOrange_33", withExtension: "cube"))
        let lut = try CubeLUTParser.parse(data: Data(contentsOf: url))
        XCTAssertEqual(lut.size, 33)
    }
}
