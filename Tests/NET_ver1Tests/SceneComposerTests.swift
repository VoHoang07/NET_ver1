import CoreGraphics
import XCTest
@testable import NET_ver1

/// Test cho phần "app quyết bố cục và chấm khớp".
///
/// Toàn bộ logic nằm trong hàm thuần nên test được không cần camera — đây là lý do
/// các lớp này tách khỏi `CameraService`.
final class SceneComposerTests: XCTestCase {

    // MARK: - Bố cục

    func testLayoutKeepsSubjectNearEyeLine() {
        let pose = ShootingPose.seatedStraight
        guard let layout = SceneComposer.layout(
            pose: pose, viewport: CGSize(width: 390, height: 520)
        ) else {
            return XCTFail("Không tạo được bố cục cho khung hợp lệ")
        }

        // Tâm người phải nằm giữa đường mắt và tâm thân.
        XCTAssertGreaterThan(layout.subjectCenter.y, pose.eyeLineRatio)
        XCTAssertLessThan(layout.subjectCenter.y, pose.bodyCenterY)
        XCTAssertEqual(layout.subjectCenter.x, 0.5, accuracy: 0.001)
    }

    func testLayoutCentersSubjectHorizontally() {
        for pose in ShootingPose.all {
            guard let layout = SceneComposer.layout(
                pose: pose, viewport: CGSize(width: 390, height: 520)
            ) else {
                return XCTFail("Không tạo được bố cục cho \(pose.id)")
            }
            XCTAssertEqual(layout.subjectCenter.x, 0.5, accuracy: 0.001)
        }
    }

    func testLayoutReturnsNilForZeroViewport() {
        let pose = ShootingPose.seatedStraight
        XCTAssertNil(SceneComposer.layout(pose: pose, viewport: .zero))
    }

    /// Bề ngang thân chuẩn hoá theo **chiều ngang**, chiều cao đầu theo **chiều cao**.
    /// Trộn hai trục là lỗi sai lệch ~30%.
    func testWidthAndHeightUseDifferentAxes() {
        let pose = ShootingPose.seatedStraight
        let viewport = CGSize(width: 300, height: 600)
        guard let layout = SceneComposer.layout(pose: pose, viewport: viewport) else {
            return XCTFail("Không tạo được bố cục")
        }

        XCTAssertEqual(
            layout.headHeightRatio, pose.headHeightRatio, accuracy: 0.001,
            "Chiều cao đầu phải theo chiều cao khung"
        )

        // Bề vai = chiều cao đầu (px) × nhân thân chuẩn, rồi chia chiều ngang khung.
        let expectedShoulder = layout.headHeightRatio * viewport.height
            * BodyCanon.Width.shoulder
        XCTAssertEqual(
            layout.subjectWidthRatio, expectedShoulder / viewport.width, accuracy: 0.001
        )
    }

    func testSeatedPosesUseTableAndStandingDoNot() {
        for pose in ShootingPose.all where pose.stance == .seated {
            XCTAssertTrue(pose.usesTable, "\(pose.id) ngồi thì phải có bàn")
        }
        for pose in ShootingPose.all where pose.stance == .standing {
            XCTAssertFalse(pose.usesTable, "\(pose.id) đứng thì không có bàn")
        }
    }

    // MARK: - Zoom

    /// Phòng đủ chỗ thì không zoom.
    func testNoZoomWhenRoomIsDeepEnough() {
        let pose = ShootingPose.standingStraight
        // Khoảng cách mong muốn = standoff × chiều cao đầu.
        let wanted = pose.standoffInHeads * BodyPoseReference.typicalHeadHeight
        let zoom = SceneComposer.suggestedZoom(
            pose: pose,
            viewport: CGSize(width: 390, height: 520),
            availableDepth: wanted * 2,
            currentZoom: 1
        )
        XCTAssertEqual(zoom, SceneComposer.minimumZoom, accuracy: 0.001)
    }

    /// Phòng chật thì phải zoom vào để bù.
    func testZoomsInWhenRoomIsTooShallow() {
        let pose = ShootingPose.standingStraight
        let wanted = pose.standoffInHeads * BodyPoseReference.typicalHeadHeight
        let zoom = SceneComposer.suggestedZoom(
            pose: pose,
            viewport: CGSize(width: 390, height: 520),
            availableDepth: wanted / 2,
            currentZoom: 1
        )
        XCTAssertGreaterThan(zoom, 1.2)
    }

    /// Zoom có trần. Không có trần thì nén tele quá tay, ảnh mất chi tiết.
    func testZoomNeverExceedsCap() {
        let pose = ShootingPose.standingStraight
        let zoom = SceneComposer.suggestedZoom(
            pose: pose,
            viewport: CGSize(width: 390, height: 520),
            availableDepth: 0.3,
            currentZoom: 1
        )
        XCTAssertLessThanOrEqual(zoom, SceneComposer.maximumZoom)
    }

    func testZoomNeverGoesBelowOne() {
        let pose = ShootingPose.standingStraight
        let zoom = SceneComposer.suggestedZoom(
            pose: pose,
            viewport: CGSize(width: 390, height: 520),
            availableDepth: 100,
            currentZoom: 1
        )
        XCTAssertGreaterThanOrEqual(zoom, SceneComposer.minimumZoom)
    }

    /// Chưa quét phòng thì giữ nguyên zoom hiện tại, không đoán bừa.
    func testZoomUnchangedWhenDepthUnknown() {
        let pose = ShootingPose.seatedLean
        let zoom = SceneComposer.suggestedZoom(
            pose: pose,
            viewport: CGSize(width: 390, height: 520),
            availableDepth: nil,
            currentZoom: 1.4
        )
        XCTAssertEqual(zoom, 1.4, accuracy: 0.001)
    }
}

// MARK: - Chấm khớp

final class PostureMatchTests: XCTestCase {

    private func layout() -> SceneComposer.Layout? {
        SceneComposer.layout(
            pose: .seatedStraight, viewport: CGSize(width: 390, height: 520)
        )
    }

    /// Người đúng chỗ thì khớp.
    func testPerfectAlignmentIsAligned() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.hasSubject = true
        m.bodyPose = Self.standingPose(centerX: 0.5, widthRatio: layout.subjectWidthRatio)

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertTrue(match.isAligned, "Đứng đúng khuôn phải khớp")
        XCTAssertEqual(match.score, 1, accuracy: 0.01)
    }

    func testTooFarLeftAsksToMoveRight() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.bodyPose = Self.standingPose(centerX: 0.5 - 0.20, widthRatio: layout.subjectWidthRatio)

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertEqual(match.adjustment, .moveRight)
    }

    func testTooFarRightAsksToMoveLeft() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.bodyPose = Self.standingPose(centerX: 0.5 + 0.20, widthRatio: layout.subjectWidthRatio)

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertEqual(match.adjustment, .moveLeft)
    }

    /// Bề ngang nhỏ hơn khuôn = người ở xa.
    func testSmallSubjectAsksToComeCloser() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.bodyPose = Self.standingPose(
            centerX: 0.5, widthRatio: layout.subjectWidthRatio * 0.5
        )

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertEqual(match.adjustment, .tooClose)
    }

    func testLargeSubjectAsksToStepBack() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.bodyPose = Self.standingPose(
            centerX: 0.5, widthRatio: layout.subjectWidthRatio * 1.8
        )

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertEqual(match.adjustment, .tooFar)
    }

    /// Không thấy người thì báo tìm chỗ sáng hơn, không đoán bừa.
    func testMissingPoseAsksForLight() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = false

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        guard case .pose(let criterion, let hint) = match.adjustment else {
            return XCTFail("Phải báo tìm người, mà ra \(match.adjustment)")
        }
        XCTAssertEqual(criterion, .posture)
        XCTAssertTrue(hint.contains("sáng"), "Câu gợi ý phải nói về ánh sáng")
    }

    /// Sai một chút thì chấp nhận — người mẫu không tạo dáng máy đo chính xác.
    func testSmallDeviationStillPasses() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        m.bodyPose = Self.standingPose(
            centerX: 0.5 + PostureMatch.centerTolerance * 0.6,
            widthRatio: layout.subjectWidthRatio * 1.03
        )

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertTrue(match.isAligned, "Sai nhỏ thì không được bắt lỗi — sẽ phiền")
    }

    /// Vai nghiêng lệch lớn thì báo, nhưng ngưỡng phải rộng.
    func testExtremeShoulderTiltIsFlagged() {
        guard let layout = layout() else { return XCTFail("Thiếu bố cục") }

        var m = CaptureMeasurements()
        m.hasPerson = true
        var pose = Self.standingPose(centerX: 0.5, widthRatio: layout.subjectWidthRatio)
        // Tư thế chọn là ngồi thẳng (vai ngang), người thật nghiêng 40°.
        pose.joints.leftShoulder = CGPoint(x: 0.3, y: 0.7)
        pose.joints.rightShoulder = CGPoint(x: 0.7, y: 0.5)
        m.bodyPose = pose

        let match = PostureMatch.evaluate(pose: .seatedStraight, measurements: m, layout: layout)
        XCTAssertFalse(match.isAligned, "Vai nghiêng 40° phải bị bắt")
    }

    // MARK: - Tiện ích

    private static func standingPose(centerX: CGFloat, widthRatio: CGFloat) -> BodyPose {
        let half = widthRatio / 2
        let shoulderY: CGFloat = 0.55
        let hipY: CGFloat = 0.72

        var joints = BodyPose.Joints()
        joints.nose = CGPoint(x: centerX, y: 0.38)
        joints.neck = CGPoint(x: centerX, y: 0.44)
        joints.leftShoulder = CGPoint(x: centerX - half, y: shoulderY)
        joints.rightShoulder = CGPoint(x: centerX + half, y: shoulderY)
        joints.leftHip = CGPoint(x: centerX - half * 0.72, y: hipY)
        joints.rightHip = CGPoint(x: centerX + half * 0.72, y: hipY)
        return BodyPose(joints: joints)
    }
}