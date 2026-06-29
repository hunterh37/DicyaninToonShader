import XCTest
import simd
@testable import DicyaninToonShader

final class DicyaninToonShaderTests: XCTestCase {

    func testComponentDefaults() {
        let c = ToonShadedComponent()
        XCTAssertEqual(c.mode, .full)
        XCTAssertEqual(c.bands, 3)
        XCTAssertFalse(c.applied)
        XCTAssertEqual(c.outlineColor, SIMD3<Float>(0, 0, 0))
        XCTAssertGreaterThan(c.outlineScale, 1.0)
    }

    func testOutlineOnlyMode() {
        let c = ToonShadedComponent(mode: .outlineOnly)
        XCTAssertEqual(c.mode, .outlineOnly)
    }

    func testCustomInit() {
        let c = ToonShadedComponent(baseColor: [1, 0, 0],
                                    mode: .full,
                                    outlineColor: [0, 0, 1],
                                    outlineScale: 1.1,
                                    bands: 5)
        XCTAssertEqual(c.baseColor, SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(c.outlineColor, SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(c.outlineScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(c.bands, 5)
    }
}
