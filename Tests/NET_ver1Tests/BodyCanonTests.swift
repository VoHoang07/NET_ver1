import XCTest
@testable import NET_ver1

/// Test hằng số nhân thân và thông số khuôn.
///
/// Ranh giới này quyết định khuôn có đúng tỉ lệ chuyên nghiệp hay không, nên cần
/// ghim lại bằng test thay vì tin vào con số viết tay.
final class BodyCanonTests: XCTestCase {

    // MARK: - Nhân thân

    func testMarkersAreInAnatomicalOrder() {
        let ordered: [BodyCanon.Marker] = [
            .topOfHead, .eyeLine, .chin, .shoulder, .chest, .navel, .hip, .knee, .foot
        ]
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(
                previous.heightFromTop, next.heightFromTop,
                "\(previous) phải nằm cao hơn \(next)"
            )
        }
    }

    func testEyeIsHalfwayBetweenTopOfHeadAndChin() {
        XCTAssertEqual(BodyCanon.Marker.eyeLine.heightFromTop, 0.5)
        XCTAssertEqual(BodyCanon.Marker.chin.heightFromTop, 1.0)
    }

    func testTotalHeightIsSevenAndAHalfHeads() {
        XCTAssertEqual(BodyCanon.totalHeightInHeads, 7.5)
        XCTAssertEqual(BodyCanon.Marker.foot.heightFromTop, BodyCanon.totalHeightInHeads)
    }

    func testShoulderToHeadRatioIsPhotographicRange() {
        // Chuẩn thường nằm trong khoảng 2.5–3.0 bề vai / bề đầu.
        let ratio = BodyCanon.Width.shoulderToHeadRatio
        XCTAssertGreaterThan(ratio, 2.5)
        XCTAssertLessThan(ratio, 3.0)
    }

    func testWidthsAreWiderGoingUpTheBody() {
        XCTAssertLessThan(BodyCanon.Width.head, BodyCanon.Width.hip)
        XCTAssertLessThan(BodyCanon.Width.hip, BodyCanon.Width.shoulder)
    }

    func testHeightMultiplierScalesWholeBody() {
        let head: CGFloat = 0.17
        let personHeight = BodyCanon.heightMultiplier(headHeight: head)
        XCTAssertEqual(personHeight, 7.5 * 0.17, accuracy: 0.0001)
    }

    // MARK: - Thông số khuôn

    func testPortraitEyeSitsOnThirdsLine() {
        XCTAssertEqual(PoseTemplate.portrait.eyeLineRatio, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testTemplateMarkersAreDerivedFromCanon() {
        let template = PoseTemplate.portrait
        let H = template.headHeightRatio

        XCTAssertEqual(template.topOfHeadRatio, template.eyeLineRatio - H * 0.5, accuracy: 0.0001)
        XCTAssertEqual(template.chinRatio, template.topOfHeadRatio + H * 1.0, accuracy: 0.0001)
        XCTAssertEqual(template.shoulderRatio, template.topOfHeadRatio + H * 1.5, accuracy: 0.0001)
        XCTAssertEqual(template.hipRatio, template.topOfHeadRatio + H * 4.0, accuracy: 0.0001)
    }

    func testTemplateMarkersAreInOrder() {
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertLessThan(template.topOfHeadRatio, template.eyeLineRatio)
            XCTAssertLessThan(template.eyeLineRatio, template.chinRatio)
            XCTAssertLessThan(template.chinRatio, template.shoulderRatio)
            XCTAssertLessThan(template.shoulderRatio, template.chestRatio)
            XCTAssertLessThan(template.chestRatio, template.hipRatio)
        }
    }

    func testShoulderLeavesRoomOnBothSides() {
        // Bề vai phải nhỏ hơn bề ngang khung để còn khoảng thở hậu khoan chỉnh.
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertLessThan(template.shoulderWidthRatio, 1.0)
            XCTAssertGreaterThan(template.shoulderWidthRatio, 0.3)
        }
    }

    func testHeadWidthMatchesCanonProportion() {
        let template = PoseTemplate.portrait
        XCTAssertEqual(
            template.headWidthRatio,
            template.headHeightRatio * BodyCanon.Width.head,
            accuracy: 0.0001
        )
    }

    func testGroupTemplateHasSmallerHead() {
        // Nhóm chụp xa hơn nên đầu phải nhỏ hơn chân dung.
        XCTAssertLessThan(PoseTemplate.group.headHeightRatio, PoseTemplate.portrait.headHeightRatio)
    }

    func testObjectModeHasNoTemplate() {
        XCTAssertNil(PoseTemplate.template(for: .object))
    }

    func testEveryBodyModeHasTemplate() {
        for mode in CaptureMode.allCases where mode.usesBodyTemplate {
            XCTAssertNotNil(PoseTemplate.template(for: mode), "\(mode.rawValue) phải có khuôn")
        }
    }

    /// Khuôn hướng dẫn phải nằm gọn trong khung, không sát đáy.
    ///
    /// Bản đầu vẽ tới `hipRatio` = 0.93, khiến góc ngoặc dưới gần chạm đáy
    /// khung — người mẫu không biết đứng ở đâu.
    func testGuideBottomLeavesRoomAtBottom() {
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertLessThan(
                template.guideBottomRatio, 0.75,
                "Đáy khuôn phải chừa chỗ, đang là \(template.guideBottomRatio)"
            )
            XCTAssertGreaterThan(template.guideBottomRatio, 0.5)
        }
    }

    func testGuideBottomIsBelowShoulder() {
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertGreaterThan(template.guideBottomRatio, template.shoulderRatio)
        }
    }

    func testGuideBottomIsShorterThanHip() {
        // Ngắn hơn hông là cố ý: đáy khuôn phải ở ngực, không ở hông.
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertLessThan(template.guideBottomRatio, template.hipRatio)
        }
    }

    func testToleranceIsPositiveAndScalesWithDistance() {
        for template in [PoseTemplate.portrait, .couple, .group] {
            XCTAssertGreaterThan(template.headTolerance, 0)
            XCTAssertGreaterThan(template.horizontalSlack, 0)
            XCTAssertGreaterThan(template.topHeadSlack, 0)
        }
        // Chụp xa hơn thì sai số cho phép lớn hơn.
        XCTAssertGreaterThan(PoseTemplate.group.headTolerance, PoseTemplate.portrait.headTolerance)
    }
}
