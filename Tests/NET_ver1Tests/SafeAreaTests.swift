import XCTest
@testable import NET_ver1

/// Test phép ánh xạ toạ độ — nơi dễ sai nhất vì ảnh thật bị cắt theo
/// `resizeAspectFill` còn khuôn thì vẽ trên khung hiển thị.
final class SafeAreaTests: XCTestCase {

    private let epsilon: CGFloat = 0.0001

    // MARK: - Tính tỉ lệ cắt

    func testEqualAspectHasNoCrop() {
        let safe = SafeArea(
            viewSize: CGSize(width: 300, height: 400),
            bufferSize: CGSize(width: 1200, height: 1600)
        )
        XCTAssertEqual(safe.horizontalCrop, 0, accuracy: epsilon)
        XCTAssertEqual(safe.verticalCrop, 0, accuracy: epsilon)
        XCTAssertEqual(safe.visibleWidthRatio, 1, accuracy: epsilon)
        XCTAssertEqual(safe.visibleHeightRatio, 1, accuracy: epsilon)
    }

    /// Khung 3:4 (dọc) lấp bằng buffer 4:3 (ngang) -> phải cắt **chiều ngang**.
    func testNarrowViewInsideWideBufferCropsSides() {
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        XCTAssertEqual(safe.horizontalCrop, 0.2188, accuracy: 0.001)
        XCTAssertEqual(safe.verticalCrop, 0, accuracy: epsilon)
        XCTAssertLessThan(safe.visibleWidthRatio, 1)
        XCTAssertEqual(safe.visibleHeightRatio, 1, accuracy: epsilon)
    }

    /// Khung 4:3 (ngang) lấp bằng buffer 3:4 (dọc) -> phải cắt **chiều dọc**.
    func testWideViewInsideTallBufferCropsTopAndBottom() {
        let safe = SafeArea(
            viewSize: CGSize(width: 4, height: 3),
            bufferSize: CGSize(width: 3, height: 4)
        )
        XCTAssertEqual(safe.verticalCrop, 0.2188, accuracy: 0.001)
        XCTAssertEqual(safe.horizontalCrop, 0, accuracy: epsilon)
        XCTAssertLessThan(safe.visibleHeightRatio, 1)
        XCTAssertEqual(safe.visibleWidthRatio, 1, accuracy: epsilon)
    }

    func testAspectFitDoesNotCrop() {
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3),
            fillsView: false
        )
        XCTAssertEqual(safe.horizontalCrop, 0, accuracy: epsilon)
        XCTAssertEqual(safe.verticalCrop, 0, accuracy: epsilon)
    }

    func testZeroSizeDoesNotDivideByZero() {
        let safe = SafeArea(viewSize: .zero, bufferSize: CGSize(width: 4, height: 3))
        XCTAssertEqual(safe.horizontalCrop, 0, accuracy: epsilon)
        XCTAssertEqual(safe.verticalCrop, 0, accuracy: epsilon)
    }

    // MARK: - Ánh xạ điểm

    func testCenterMapsToCenterWhenNoCrop() {
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 1200, height: 1600)
        )
        let result = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(result.x, 0.5, accuracy: epsilon)
        XCTAssertEqual(result.y, 0.5, accuracy: epsilon)
    }

    func testVerticalFlipIsApplied() {
        // Vision đo từ đáy ảnh, khung hiển thị đo từ trên xuống.
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 1200, height: 1600)
        )
        let bottomOfImage = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 0.0))
        XCTAssertEqual(bottomOfImage.y, 1.0, accuracy: epsilon, "Đáy ảnh phải nằm dưới khung")

        let topOfImage = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 1.0))
        XCTAssertEqual(topOfImage.y, 0.0, accuracy: epsilon, "Đỉnh ảnh phải nằm trên khung")
    }

    func testCroppedAxisMapsVisibleEdgesToViewEdges() {
        // Cắt chiều ngang: mép CỦA VÙNG ẢNH CÒN LẠI phải trùng mép khung.
        // (Điểm nằm ngoài vùng còn lại — tức trong phần bị cắt — sẽ nằm ngoài khung,
        //  và đó là hành vi đúng.)
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        let leftVisible = safe.viewPoint(fromVisionPoint: CGPoint(x: safe.horizontalCrop, y: 0.5))
        XCTAssertEqual(leftVisible.x, 0.0, accuracy: epsilon)

        let rightVisible = safe.viewPoint(
            fromVisionPoint: CGPoint(x: 1 - safe.horizontalCrop, y: 0.5)
        )
        XCTAssertEqual(rightVisible.x, 1.0, accuracy: epsilon)
    }

    func testPointOutsideVisibleRegionLandsOutsideView() {
        // Phần bị cắt không được hiển thị -> toạ độ nằm ngoài 0...1.
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        let croppedAway = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.0, y: 0.5))
        XCTAssertLessThan(croppedAway.x, 0.0)

        let otherSide = safe.viewPoint(fromVisionPoint: CGPoint(x: 1.0, y: 0.5))
        XCTAssertGreaterThan(otherSide.x, 1.0)
    }

    func testUncroppedAxisIsPreservedExactly() {
        // Không cắt chiều dọc thì toạ độ dọc phải giữ nguyên (kể cả đảo chiều Y).
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        XCTAssertEqual(safe.verticalCrop, 0, accuracy: epsilon)
        let bottomEdge = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 0.0))
        XCTAssertEqual(bottomEdge.y, 1.0, accuracy: epsilon)
        let topEdge = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 1.0))
        XCTAssertEqual(topEdge.y, 0.0, accuracy: epsilon)
    }

    func testImageCenterAlwaysMapsToViewCenter() {
        // Bất kể cắt bao nhiêu, tâm ảnh thật vẫn phải trùng tâm khung hiển thị.
        // Đây là bất biến quan trọng nhất — lệch nó là khuôn bị lệch.
        for view in [CGSize(width: 3, height: 4), CGSize(width: 4, height: 3), CGSize(width: 1, height: 1)] {
            for buffer in [CGSize(width: 4, height: 3), CGSize(width: 16, height: 9), CGSize(width: 3, height: 4)] {
                let safe = SafeArea(viewSize: view, bufferSize: buffer)
                let center = safe.viewPoint(fromVisionPoint: CGPoint(x: 0.5, y: 0.5))
                XCTAssertEqual(center.x, 0.5, accuracy: epsilon, "view \(view) buffer \(buffer)")
                XCTAssertEqual(center.y, 0.5, accuracy: epsilon, "view \(view) buffer \(buffer)")
            }
        }
    }

    // MARK: - Ánh xạ hình chữ nhật

    func testRectMappingKeepsCenterAndScalesCroppedAxis() {
        // Cắt chiều ngang -> cùng vùng phải hiển thị RỘNG hơn, chiều cao giữ nguyên.
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        let rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let mapped = safe.viewRect(fromVisionRect: rect)

        XCTAssertEqual(mapped.midX, 0.5, accuracy: epsilon)
        XCTAssertEqual(mapped.midY, 0.5, accuracy: epsilon)
        XCTAssertGreaterThan(mapped.width, rect.width, "Cắt ngang thì cùng vùng phải hiển thị rộng hơn")
        XCTAssertEqual(mapped.height, rect.height, accuracy: epsilon, "Không cắt dọc thì chiều cao giữ nguyên")
    }

    func testRectMappingWhenNoCropKeepsSize() {
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 1200, height: 1600)
        )
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let mapped = safe.viewRect(fromVisionRect: rect)
        XCTAssertEqual(mapped.width, 0.4, accuracy: epsilon)
        XCTAssertEqual(mapped.height, 0.4, accuracy: epsilon)
        XCTAssertEqual(mapped.midX, rect.midX, accuracy: epsilon)
    }

    func testVisibleRegionRectFillsView() {
        // Hình chữ nhật đúng bằng vùng ảnh còn lại phải phủ kín khung.
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        let visibleRegion = CGRect(
            x: safe.horizontalCrop,
            y: safe.verticalCrop,
            width: safe.visibleWidthRatio,
            height: safe.visibleHeightRatio
        )
        let mapped = safe.viewRect(fromVisionRect: visibleRegion)
        XCTAssertEqual(mapped.minX, 0.0, accuracy: 0.001)
        XCTAssertEqual(mapped.minY, 0.0, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 1.0, accuracy: 0.01)
        XCTAssertEqual(mapped.height, 1.0, accuracy: 0.01)
    }

    func testVerticallyCenteredRectStaysCenteredAfterFlip() {
        // Bbox nằm quanh giữa ảnh phải vẫn nằm quanh giữa khung sau khi lật Y.
        let safe = SafeArea(
            viewSize: CGSize(width: 3, height: 4),
            bufferSize: CGSize(width: 4, height: 3)
        )
        let rect = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        let mapped = safe.viewRect(fromVisionRect: rect)
        XCTAssertEqual(mapped.midY, 0.5, accuracy: 0.001)
    }

    // MARK: - Xoay buffer

    func testRotatedBufferChangesCrop() {
        let landscape = CGSize(width: 1920, height: 1080)
        let portrait = landscape.rotated(byDegrees: 90)
        XCTAssertEqual(portrait.width, 1080, accuracy: epsilon)
        XCTAssertEqual(portrait.height, 1920, accuracy: epsilon)

        let before = SafeArea(viewSize: CGSize(width: 3, height: 4), bufferSize: landscape)
        let after = SafeArea(viewSize: CGSize(width: 3, height: 4), bufferSize: portrait)
        XCTAssertNotEqual(before.verticalCrop, after.verticalCrop)
    }

    func testRotationIsIdempotentForQuarterTurns() {
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(size.rotated(byDegrees: 180), size)
        XCTAssertEqual(size.rotated(byDegrees: 360), size)
        XCTAssertEqual(size.rotated(byDegrees: 0), size)
    }

    func testNegativeRotationNormalizes() {
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(size.rotated(byDegrees: -90), size.rotated(byDegrees: 270))
    }
}
