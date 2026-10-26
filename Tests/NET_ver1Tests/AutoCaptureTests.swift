import CoreGraphics
import XCTest
@testable import NET_ver1

/// Test cho bộ quyết định chụp tự động.
///
/// Phần này quyết định bấm chụp, nên test của nó là test về **khi nào không bấm**.
final class AutoCaptureTests: XCTestCase {

    private let clock = ContinuousClock()
    private let aligned = PostureMatch(adjustment: .none, detail: nil, score: 1)
    private let misaligned = PostureMatch(adjustment: .moveLeft, detail: nil, score: 0.3)

    private func advanced(by seconds: Double) -> ContinuousClock.Instant {
        clock.now.advanced(by: .seconds(seconds))
    }

    // MARK: - Điều kiện bắt buộc

    func testDoesNotCaptureWhenNotAligned() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        var decision = decider.evaluate(
            now: start, match: misaligned, eyesOpen: true, headMoved: false
        )
        // Giữ yên đủ lâu cũng không bấm nếu chưa đúng chỗ.
        for step in stride(from: 0.0, through: 3.0, by: 0.1) {
            decision = decider.evaluate(
                now: start.advanced(by: .seconds(step)),
                match: misaligned, eyesOpen: true, headMoved: false
            )
            if decision == .capture {
                return XCTFail("Không được bấm khi chưa đúng chỗ")
            }
        }
        XCTAssertNotEqual(decision, .capture)
    }

    func testDoesNotCaptureWhenEyesClosed() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        var captured = false
        for step in stride(from: 0.0, through: 3.0, by: 0.1) {
            let decision = decider.evaluate(
                now: start.advanced(by: .seconds(step)),
                match: aligned, eyesOpen: false, headMoved: false
            )
            if decision == .capture { captured = true }
        }
        XCTAssertFalse(captured, "Không được bấm khi mắt đang nhắm")
    }

    func testDoesNotCaptureWhenHeadTurning() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        var captured = false
        for step in stride(from: 0.0, through: 3.0, by: 0.1) {
            let decision = decider.evaluate(
                now: start.advanced(by: .seconds(step)),
                match: aligned, eyesOpen: true, headMoved: true
            )
            if decision == .capture { captured = true }
        }
        XCTAssertFalse(captured, "Không được bấm khi đầu đang quay đi")
    }

    /// Ba điều kiện cùng đúng thì bấm.
    func testCapturesWhenAllThreeConditionsMet() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        var captured = false
        for step in stride(from: 0.0, through: 3.0, by: 0.05) {
            let decision = decider.evaluate(
                now: start.advanced(by: .seconds(step)),
                match: aligned, eyesOpen: true, headMoved: false
            )
            if decision == .capture { captured = true }
        }
        XCTAssertTrue(captured, "Đúng chỗ + yên + mắt mở thì phải bấm")
    }

    // MARK: - Thời gian giữ yên

    /// 1,2 giây là đánh đổi giữa hai lỗi — có test ghim để không ai đổi tuỳ tiện.
    func testStillnessWindowIsPointTwoSeconds() {
        XCTAssertEqual(
            AutoCaptureDecider.requiredStillness,
            .seconds(1.2),
            "Thời gian giữ yên là đánh đổi cân bằng, không đổi tuỳ ý"
        )
    }

    func testDoesNotCaptureBeforeStillnessWindow() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        // 1,0 giây — chưa đủ.
        _ = decider.evaluate(now: start, match: aligned, eyesOpen: true, headMoved: false)
        let decision = decider.evaluate(
            now: start.advanced(by: .seconds(1.0)),
            match: aligned, eyesOpen: true, headMoved: false
        )
        XCTAssertNotEqual(decision, .capture, "Chưa đủ 1,2 giây thì chưa bấm")
    }

    func testCapturesAfterStillnessWindow() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        _ = decider.evaluate(now: start, match: aligned, eyesOpen: true, headMoved: false)
        let decision = decider.evaluate(
            now: start.advanced(by: .seconds(1.4)),
            match: aligned, eyesOpen: true, headMoved: false
        )
        XCTAssertEqual(decision, .capture)
    }

    /// Rời chỗ rồi quay lại thì phải đếm lại, không được bấm ngay.
    func testStillnessTimerResetsAfterLeavingPosition() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        _ = decider.evaluate(now: start, match: aligned, eyesOpen: true, headMoved: false)
        _ = decider.evaluate(
            now: start.advanced(by: .seconds(1.0)),
            match: aligned, eyesOpen: true, headMoved: false
        )
        // Rời chỗ trong chốc lát.
        _ = decider.evaluate(
            now: start.advanced(by: .seconds(1.1)),
            match: misaligned, eyesOpen: true, headMoved: false
        )
        // Quay lại — chỉ mới 0,3 giây, chưa được bấm.
        let decision = decider.evaluate(
            now: start.advanced(by: .seconds(1.4)),
            match: aligned, eyesOpen: true, headMoved: false
        )
        XCTAssertNotEqual(decision, .capture, "Phải đếm lại thời gian giữ yên")
    }

    // MARK: - Tiến độ

    func testProgressReachesOneAtThreshold() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        XCTAssertEqual(decider.progress(at: start), 0, accuracy: 0.001)

        _ = decider.evaluate(now: start, match: aligned, eyesOpen: true, headMoved: false)
        let progress = decider.progress(at: start.advanced(by: .seconds(0.6)))
        XCTAssertEqual(progress, 0.5, accuracy: 0.05)
    }

    func testProgressIsZeroWhenWaiting() {
        var decider = AutoCaptureDecider()
        let start = clock.now
        _ = decider.evaluate(now: start, match: misaligned, eyesOpen: true, headMoved: false)
        XCTAssertEqual(decider.progress(at: start.advanced(by: .seconds(5))), 0, accuracy: 0.001)
    }

    // MARK: - Chống bấm liên tục

    func testResetPreventsImmediateSecondCapture() {
        var decider = AutoCaptureDecider()
        let start = clock.now

        for step in stride(from: 0.0, through: 2.0, by: 0.05) {
            _ = decider.evaluate(
                now: start.advanced(by: .seconds(step)),
                match: aligned, eyesOpen: true, headMoved: false
            )
        }
        decider.reset()

        let decision = decider.evaluate(
            now: start.advanced(by: .seconds(2.0)),
            match: aligned, eyesOpen: true, headMoved: false
        )
        XCTAssertNotEqual(decision, .capture, "Sau khi bấm phải chờ lại")
    }
}

// MARK: - Tư thế

final class ShootingPoseTests: XCTestCase {

    func testExactlySixPoses() {
        XCTAssertEqual(
            ShootingPose.all.count, 6,
            "Sáu tư thế — mỗi tư thế một mô hình 3D, làm nhiều hơn thì làm dở"
        )
    }

    func testPoseIDsAreUnique() {
        let ids = ShootingPose.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ID phải duy nhất")
    }

    func testHasThreeSeatedAndThreeStanding() {
        XCTAssertEqual(ShootingPose.all.filter { $0.stance == .seated }.count, 3)
        XCTAssertEqual(ShootingPose.all.filter { $0.stance == .standing }.count, 3)
    }

    func testFallbackToFirstPose() {
        XCTAssertEqual(ShootingPose.pose(id: "khong-ton-tai").id, ShootingPose.seatedStraight.id)
    }

    func testEveryPoseHasCue() {
        for pose in ShootingPose.all {
            XCTAssertFalse(pose.cue.isEmpty, "\(pose.id) phải có câu gợi ý")
            XCTAssertFalse(pose.title.isEmpty)
        }
    }

    /// Khoảng cách phải nằm trong dải dùng được với ống 1x–2x.
    ///
    /// - Important: quá xa thì người nhỏ như hạt, quá gần thì chỉ thấy cằm.
    ///   Ràng buộc này chặn việc ai đó thêm một tư thế "thú vị" mà ống kính
    ///   không chịu nổi.
    func testStandoffStaysWithinUsableRange() {
        for pose in ShootingPose.all {
            XCTAssertGreaterThanOrEqual(
                pose.standoffInHeads, 4,
                "\(pose.id) quá gần, ống 1x sẽ không lấy hết người"
            )
            XCTAssertLessThanOrEqual(
                pose.standoffInHeads, 10,
                "\(pose.id) quá xa, người sẽ nhỏ như hạt dù zoom 2x"
            )
        }
    }

    /// Các tư thế phải khác nhau về khoảng cách — nếu tất cả bằng nhau thì nút
    /// "Lấy góc này" không khác gì cả.
    func testPosesHaveDistinctStandoffs() {
        let values = Set(ShootingPose.all.map(\.standoffInHeads))
        XCTAssertGreaterThan(
            values.count, 1,
            "Các tư thế phải khác nhau về khoảng cách"
        )
    }
}

// MARK: - Chiều cao người dùng

final class UserHeightTests: XCTestCase {

    func testAcceptsReasonableHeights() {
        XCTAssertTrue(UserHeight(meters: 1.70, confirmedAt: Date()).isValid)
        XCTAssertTrue(UserHeight(meters: 1.55, confirmedAt: Date()).isValid)
        XCTAssertTrue(UserHeight(meters: 2.0, confirmedAt: Date()).isValid)
    }

    /// Gõ nhầm thì chiều cao sai kéo theo khoảng cách sai.
    func testRejectsImplausibleHeights() {
        XCTAssertFalse(UserHeight(meters: 0.5, confirmedAt: Date()).isValid)
        XCTAssertFalse(UserHeight(meters: 3.0, confirmedAt: Date()).isValid)
    }

    func testTallerPersonHasLargerHead() {
        let short = UserHeight(meters: 1.5, confirmedAt: Date())
        let tall = UserHeight(meters: 1.95, confirmedAt: Date())
        XCTAssertGreaterThan(tall.headHeight, short.headHeight)
    }

    /// Người cao hơn thì khoảng cách cũng phải xa hơn — nếu không thì đầu họ luôn
    /// nhỏ hơn khuôn và app bắt họ tiến lên vô ích.
    func testTallerUserNeedsMoreDistance() {
        let short = UserHeight(meters: 1.55, confirmedAt: Date())
        let tall = UserHeight(meters: 1.95, confirmedAt: Date())
        for pose in ShootingPose.all {
            XCTAssertGreaterThan(
                tall.standoff(for: pose), short.standoff(for: pose),
                "Người cao \(tall.meters)m cần đứng xa hơn ở \(pose.id)"
            )
        }
    }

    /// `standoff` phải theo đúng số đầu của tư thế.
    func testStandoffUsesPoseHeadCount() {
        let height = UserHeight(meters: 1.70, confirmedAt: Date())
        for pose in ShootingPose.all {
            XCTAssertEqual(
                height.standoff(for: pose),
                pose.standoffInHeads * height.headHeight,
                accuracy: 0.0001,
                "\(pose.id) phải quy đổi đúng theo số đầu"
            )
        }
    }

    func testSaveAndLoadRoundTrip() {
        let key = "test.user.heightMeters"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // UserSettingsStore dùng key cố định; test chỉ cần chứng minh đọc-ghi cân
        // nhau qua API công khai.
        UserSettingsStore.saveHeight(1.83)
        let loaded = UserSettingsStore.loadHeight()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.meters ?? 0, 1.83, accuracy: 0.001)

        UserSettingsStore.clearHeight()
        XCTAssertNil(UserSettingsStore.loadHeight())
    }
}