import CoreGraphics
import Foundation

/// So tư thế người thật với tư thế đã chọn.
///
/// ## Vì sao chỉ một chỉ dẫn
///
/// Người đang chụp không đọc nổi "vai lệch 12.3°". Họ chỉ cần biết **dịch sang
/// bên nào, xa bao nhiêu**. Nên `PostureMatch` trả về đúng một mũi tên, và phần
/// số để dành cho `detail` — nơi không ai nhìn thấy.
nonisolated struct PostureMatch: Equatable {

    /// Hướng cần sửa. `nil` = đã đúng.
    nonisolated enum Adjustment: Equatable {
        /// Người đang lệch so với tâm khung.
        case moveLeft
        case moveRight
        /// Người đang quá gần — cần lùi (hoặc app zoom out).
        case tooClose
        /// Người đang quá xa — cần tiến lại (hoặc app zoom in).
        case tooFar
        /// Tư thế chưa đúng — đưa đủ thông tin để hiện câu ngắn.
        case pose(criterion: QualityCriterion, hint: String)

        /// Dùng khi đạt: xanh, không hiện mũi tên.
        case none
    }

    var adjustment: Adjustment
    /// Chi tiết kỹ thuật, không hiện lên màn hình.
    var detail: String?

    /// Đạt khi **không còn tiêu chí nào** chưa ổn.
    ///
    /// - Important: đây là định nghĩa **duy nhất** của "đã khớp". Không dùng
    ///   `score >= idealThreshold` thay thế — hai cái đó chỉ trùng nhau do các hằng
    ///   số tình cờ khớp, nên đổi ngưỡng một chỗ sẽ khiến chụp tự động bấm lúc app
    ///   vẫn báo chưa khớp.
    var isAligned: Bool { adjustment == .none }

    /// Điểm 0...1, dùng cho **tiến độ hiển thị** — không quyết định khớp hay không.
    var score: CGFloat

    /// Ngưỡng để vẽ tiến độ. Không đặt quá cao: tiến độ nhảy tới 100% rồi đứng
    /// yên nhìn rất kỳ, còn vẫn chưa chụp thì thành không bấm còn hơn.
    nonisolated static let idealThreshold: CGFloat = 0.8

    // MARK: - Ngưỡng

    /// Sai lệch vị trí tâm cho phép, chuẩn hoá theo chiều ngang khung.
    nonisolated static let centerTolerance: CGFloat = 0.06
    /// Sai lệch chiều cao đầu cho phép.
    nonisolated static let scaleTolerance: CGFloat = 0.05

    // MARK: - Chấm

    static func evaluate(
        pose: ShootingPose,
        measurements: CaptureMeasurements,
        layout: SceneComposer.Layout?
    ) -> PostureMatch {
        guard let bodyPose = measurements.bodyPose, bodyPose.isUsable else {
            return PostureMatch(
                adjustment: .pose(
                    criterion: .posture,
                    hint: "Chưa nhận ra người — tìm chỗ sáng hơn"
                ),
                detail: nil,
                score: 0
            )
        }

        var issues: [(score: CGFloat, adjustment: Adjustment)] = []

        // 1. Tâm người so với tâm app chọn — sai cái này thì ảnh lệch ngay.
        if let head = bodyPose.headCenter, let layout {
            let dx = head.x - layout.subjectCenter.x
            let distance = abs(dx)
            let score = max(0, 1 - distance / (centerTolerance * 3))

            if distance > centerTolerance {
                // Người lệch TRÁI (dx âm) thì phải dịch sang PHẢI để vào giữa.
                issues.append((
                    score: score,
                    adjustment: dx < 0 ? .moveRight : .moveLeft
                ))
            }
        }

        // 2. Kích thước người so với khuôn — quyết định lùi hay tiến.
        if let shoulderWidth = bodyPose.shoulderWidth, let layout {
            let ratio = shoulderWidth / layout.subjectWidthRatio
            let error = abs(ratio - 1)
            let score = max(0, 1 - error / (scaleTolerance * 4))

            if error > scaleTolerance {
                // Người NHỎ hơn khuôn (ratio < 1) nghĩa là đang đứng xa -> tiến lại.
                // Người LỚN hơn khuôn nghĩa là quá gần -> lùi ra.
                issues.append((
                    score: score,
                    adjustment: ratio < 1 ? .tooClose : .tooFar
                ))
            }
        }

        // 3. Tư thế có đúng kiểu không — vai nghiêng và thân nghiêng.
        //    Chỉ báo **hướng**, không báo độ: nghiêng 5° không phải lỗi.
        let poseIssues = poseDeviation(pose: pose, measured: bodyPose)
        issues.append(contentsOf: poseIssues)

        guard let worst = issues.min(by: { $0.score < $1.score }) else {
            return PostureMatch(
                adjustment: .none,
                detail: Self.detail(for: bodyPose),
                score: 1
            )
        }

        return PostureMatch(
            adjustment: worst.adjustment,
            detail: Self.detail(for: bodyPose),
            score: worst.score
        )
    }

    /// Chuỗi số kỹ thuật — không hiện lên màn hình, chỉ dành cho `detail`.
    private static func detail(for pose: BodyPose) -> String {
        String(
            format: "Vai nghiêng %.0f°, thân nghiêng %.0f°",
            pose.shoulderTiltDegrees ?? 0,
            pose.spineTiltDegrees ?? 0
        )
    }

    // MARK: - So tư thế

    /// Lệch tư thế thật so với tư thế đã chọn.
    ///
    /// - Important: ngưỡng **cố ý rộng**. Người mẫu không tạo dáng máy đo được
    ///   chính xác, và bắt họ chỉnh đến mức đó thì app phiền hơn là giúp.
    private static func poseDeviation(
        pose: ShootingPose,
        measured: BodyPose
    ) -> [(score: CGFloat, adjustment: Adjustment)] {
        var issues: [(score: CGFloat, adjustment: Adjustment)] = []

        if let tilt = measured.shoulderTiltDegrees {
            let error = abs(tilt - pose.shoulderTilt)
            // Sai 25° trở lại mới đáng nhắc.
            if error > 25 {
                let hint = tilt > pose.shoulderTilt
                    ? "Hạ vai phải xuống một chút"
                    : "Nhấc vai phải lên một chút"
                issues.append((
                    score: max(0, 1 - error / 50),
                    adjustment: .pose(criterion: .posture, hint: hint)
                ))
            }
        }

        if let lean = measured.spineTiltDegrees, abs(lean - pose.spineTilt) > 20 {
            let hint = lean > pose.spineTilt
                ? "Nghiêng người sang trái một chút"
                : "Nghiêng người sang phải một chút"
            issues.append((
                score: max(0, 1 - abs(lean - pose.spineTilt) / 45),
                adjustment: .pose(criterion: .posture, hint: hint)
            ))
        }

        return issues
    }
}