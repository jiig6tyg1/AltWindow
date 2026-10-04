import XCTest
import AppKit
@testable import AltWindow

final class PreviewImageTests: XCTestCase {
    func testAlreadySmallScreenshotReusesItsStorage() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let source = try XCTUnwrap(context.makeImage())
        let preview = try XCTUnwrap(PreviewImage.make(source))
        let result = try XCTUnwrap(preview.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertTrue(result === source)
        XCTAssertEqual(PreviewImage.cost(preview), 64 * 64 * 4)
    }
    func testRetinaScreenshotIsDetachedAndBounded() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 3840, height: 2160,
                                             bitsPerComponent: 8, bytesPerRow: 3840 * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let source = try XCTUnwrap(context.makeImage())
        let preview = try XCTUnwrap(PreviewImage.make(source))
        let cg = try XCTUnwrap(preview.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 760)
        XCTAssertEqual(cg.height, 427)
        XCTAssertLessThanOrEqual(PreviewImage.cost(preview), 760 * 760 * 4)
        XCTAssertFalse(cg === source)
    }
}
