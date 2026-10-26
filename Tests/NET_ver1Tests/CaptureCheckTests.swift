import XCTest
@testable import NET_ver1

/// Test cho phần domain thuần — không cần camera, không cần Vision.
///
/// Mục tiêu: bảo vệ logic chấm trạng thái khi sửa về sau, đặc biệt là các
/// quy tắc dễ sai: điều kiện cần (gate) vs điều kiện đủ, và trọng số theo mode.
final class CaptureCheckTests: XCTestCase {

    // MARK: - Fixtures

    private func perfectFrame(mode: CaptureMode) -> CaptureMeasurements {
        var m = CaptureMeasurements()
        // Với mode người, Vision chỉ trả bbox MẶT, nên fixture cũng phải là bbox
        // mặt đúng cỡ khuôn. Mode vật thể mới dùng bbox chủ thể đầy đủ.
        let template = PoseTemplate.template(for: mode)
        let faceToHead: CGFloat = 0.75
        if let template {
            let headHeight = template.headHeightRatio * faceToHead
            m.subjectRect = CGRect(
                x: 0.5 - (template.shoulderWidthRatio * 0.35) / 2,
                y: template.eyeLineRatio - headHeight * 0.5,
                width: template.shoulderWidthRatio * 0.35,
                height: headHeight
            )
        } else {
            m.subjectRect = CGRect(x: 0.30, y: 0.20, width: 0.40, height: 0.62)
        }
        m.eyePoint = CGPoint(x: 0.5, y: 1.0 / 3.0)
        m.detectedPersonCount = mode.expectedSubjectCount ?? 1
        m.overexposedRatio = 0.01
        m.underexposedRatio = 0.05
        m.centerToEdgeLuminance = 1.15
        m.sharpness = 12
        m.faceShadowRatio = 1.1
        m.horizonAngle = 0.2
        m.hasPerson = mode.usesBodyTemplate
        m.hasSubject = true
        m.backgroundClutter = 0.10
        return m
    }

    // MARK: - Trạng thái

    func testPerfectFrameIsIdeal() {
        let check = CaptureCheckEvaluator.evaluate(
            perfectFrame(mode: .solo), mode: .solo, template: nil
        )
        XCTAssertEqual(check.status, .ideal)
        XCTAssertTrue(check.failures.isEmpty)
        XCTAssertTrue(check.remainingPolish.isEmpty)
    }

    func testEmptyFrameIsNotReadyAndReportsNothing() {
        // Không có gì để đo -> không được báo "đứng sai", vì có thể chỉ là thiếu sáng.
        var empty = CaptureMeasurements()
        empty.subjectRect = nil
        empty.hasPerson = false
        empty.hasSubject = false

        let check = CaptureCheckEvaluator.evaluate(empty, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .notReady)
        XCTAssertTrue(check.results.isEmpty)
    }

    func testGateFailureForcesNotReadyEvenWhenPolishIsFine() {
        var m = perfectFrame(mode: .solo)
        m.sharpness = 1.0 // mờ

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .notReady)
        XCTAssertTrue(check.failures.contains { $0.criterion == .sharpness })
    }

    func testPolishFailureGivesGoodNotNotReady() {
        var m = perfectFrame(mode: .solo)
        m.horizonAngle = 5.0 // lệch, nhưng ảnh vẫn dùng được

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .good)
        XCTAssertTrue(check.failures.isEmpty)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .horizon })
    }

    // MARK: - Điều kiện cần

    func testOverexposedIsGateFailure() {
        var m = perfectFrame(mode: .solo)
        m.overexposedRatio = 0.30

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .notReady)
        XCTAssertTrue(check.failures.contains { $0.criterion == .lighting })
    }

    func testUnderexposedIsGateFailure() {
        var m = perfectFrame(mode: .solo)
        m.underexposedRatio = 0.40

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .notReady)
        XCTAssertTrue(check.failures.contains { $0.criterion == .lighting })
    }

    func testBacklitIsGateFailure() {
        var m = perfectFrame(mode: .solo)
        m.centerToEdgeLuminance = 0.5

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertEqual(check.status, .notReady)
        XCTAssertTrue(check.failures.contains { $0.criterion == .lighting })
    }

    func testExposureBoundariesAreInclusive() {
        // Đúng ngưỡng thì phải pass, không được báo lỗi ở biên.
        var m = perfectFrame(mode: .solo)
        m.overexposedRatio = QualityThresholds.maximumOverexposed
        m.underexposedRatio = QualityThresholds.maximumUnderexposed
        m.centerToEdgeLuminance = 0.85

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertFalse(check.failures.contains { $0.criterion == .lighting })
    }

    // MARK: - Tư thế

    func testEyeOffTemplateLineFailsPosture() {
        var m = perfectFrame(mode: .solo)
        let template = PoseTemplate.portrait
        m.eyePoint = CGPoint(x: 0.5, y: template.eyeLineRatio + 0.06)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: template)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .posture })
    }

    func testEyeInsideTolerancePassesPosture() {
        var m = perfectFrame(mode: .solo)
        let template = PoseTemplate.portrait
        m.eyePoint = CGPoint(x: 0.5, y: template.eyeLineRatio + template.headTolerance * 0.9)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: template)
        XCTAssertFalse(check.remainingPolish.contains { $0.criterion == .posture })
    }

    func testClippedHeadFailsPosture() {
        var m = perfectFrame(mode: .solo)
        m.subjectRect = CGRect(x: 0.30, y: -0.05, width: 0.40, height: 0.62)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .posture })
    }

    func testNoPersonDetectedReportsUncertainNotWrongPosture() {
        var m = perfectFrame(mode: .solo)
        m.hasPerson = false
        m.eyePoint = nil

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        let posture = check.results.first { $0.criterion == .posture }
        XCTAssertEqual(posture?.isSatisfied, false)
        XCTAssertEqual(posture?.detail, "Chưa nhận ra người trong khung")
    }

    // MARK: - Bố cục

    /// Với mode người, `subjectRect` là bbox **mặt** (Vision chỉ trả về mặt).
    /// Bản đầu dùng nhầm ngưỡng của thân người, khiến người mẫu đứng đúng khuôn
    /// vẫn bị báo sai. Test này ghim lại cách tính đúng.
    func testSoloComparesHeadHeightNotBodyHeight() {
        var m = perfectFrame(mode: .solo)
        let template = PoseTemplate.portrait
        // Vision trả bbox mặt ≈ 0.75 chiều cao đầu.
        let faceToHead: CGFloat = 0.75
        m.subjectRect = CGRect(
            x: 0.42, y: 0.28,
            width: 0.16, height: template.headHeightRatio * faceToHead
        )

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: template)
        XCTAssertFalse(
            check.remainingPolish.contains { $0.criterion == .composition },
            "Đầu đúng cỡ khuôn phải pass, không được báo sai"
        )
    }

    func testHeadTooSmallFailsComposition() {
        var m = perfectFrame(mode: .solo)
        m.subjectRect = CGRect(x: 0.47, y: 0.45, width: 0.05, height: 0.04)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        let issue = check.remainingPolish.first { $0.criterion == .composition }
        XCTAssertNotNil(issue)
        XCTAssertTrue(
            issue?.detail?.contains("Đầu nhỏ") == true,
            "Lỗi phải nói rõ đầu nhỏ, không phải kích thước chủ thể chung chung"
        )
    }

    func testHeadTooLargeFailsComposition() {
        var m = perfectFrame(mode: .solo)
        m.subjectRect = CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.30)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testObjectModeStillUsesSubjectHeightThreshold() {
        // Mode vật thể giữ nguyên cách so kích thước chủ thể.
        var m = perfectFrame(mode: .object)
        m.hasPerson = false
        m.hasSubject = true
        m.detectedPersonCount = 0
        m.subjectRect = CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .object, template: nil)
        XCTAssertFalse(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testObjectTooSmallFailsComposition() {
        var m = perfectFrame(mode: .object)
        m.hasPerson = false
        m.hasSubject = true
        m.detectedPersonCount = 0
        m.subjectRect = CGRect(x: 0.40, y: 0.60, width: 0.15, height: 0.20)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .object, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testSubjectTooLargeFailsCompositionInObjectMode() {
        var m = perfectFrame(mode: .solo)
        m.subjectRect = CGRect(x: 0.40, y: 0.60, width: 0.15, height: 0.20)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testSubjectTooLargeFailsComposition() {
        var m = perfectFrame(mode: .solo)
        m.subjectRect = CGRect(x: 0.02, y: 0.0, width: 0.96, height: 0.99)

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testSoloRejectsTwoPeople() {
        var m = perfectFrame(mode: .solo)
        m.detectedPersonCount = 2

        let check = CaptureCheckEvaluator.evaluate(m, mode: .solo, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testCoupleRejectsOnePerson() {
        var m = perfectFrame(mode: .couple)
        m.detectedPersonCount = 1

        let check = CaptureCheckEvaluator.evaluate(m, mode: .couple, template: nil)
        XCTAssertTrue(check.remainingPolish.contains { $0.criterion == .composition })
    }

    func testGroupIgnoresSubjectCount() {
        // Nhóm không ràng buộc số người -> số bất kỳ vẫn pass.
        var m = perfectFrame(mode: .group)
        m.detectedPersonCount = 7

        let check = CaptureCheckEvaluator.evaluate(m, mode: .group, template: nil)
        XCTAssertFalse(check.remainingPolish.contains { $0.criterion == .composition })
    }

    // MARK: - Trọng số theo mode

    func testObjectModeDropsPostureAndShadow() {
        var m = CaptureMeasurements()
        m.subjectRect = CGRect(x: 0.25, y: 0.30, width: 0.50, height: 0.40)
        m.hasPerson = false
        m.hasSubject = true
        m.overexposedRatio = 0.01
        m.underexposedRatio = 0.05
        m.centerToEdgeLuminance = 1.1
        m.sharpness = 12
        m.horizonAngle = 0.3
        m.backgroundClutter = 0.1

        let check = CaptureCheckEvaluator.evaluate(m, mode: .object, template: nil)
        XCTAssertFalse(check.results.contains { $0.criterion == .posture })
        XCTAssertFalse(check.results.contains { $0.criterion == .shadow })
        XCTAssertEqual(check.status, .ideal)
    }

    func testEveryModeHasTotalWeightOfOneHundred() {
        // Nếu tổng trọng số lệch, mode có ít tiêu chí sẽ bị trừ điểm oan.
        for mode in CaptureMode.allCases {
            let total = QualityCriterion.allCases.reduce(0) { $0 + $1.weight(for: mode) }
            XCTAssertEqual(total, 100, "Tổng trọng số của \(mode.rawValue) phải bằng 100, đang là \(total)")
        }
    }

    // MARK: - Hợp đồng dữ liệu

    func testCriteriaWeightsAreNonNegative() {
        for mode in CaptureMode.allCases {
            for criterion in QualityCriterion.allCases {
                XCTAssertGreaterThanOrEqual(criterion.weight(for: mode), 0)
            }
        }
    }

    func testResultListHasNoDuplicateCriteria() {
        var m = perfectFrame(mode: .group)
        m.detectedPersonCount = 3

        let check = CaptureCheckEvaluator.evaluate(m, mode: .group, template: nil)
        let ids = check.results.map(\.criterion.rawValue)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
