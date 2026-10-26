import CoreGraphics
import Foundation

// MARK: - Kết quả đo

/// Số đo thô của một khung hình, đã chuẩn hoá về cùng hệ toạ độ (0...1, gốc trên-trái).
///
/// Đây là **ranh giới** giữa phần đo đạc (cần AVFoundation/Vision) và phần chấm điểm
/// (hàm thuần). Nhờ vậy `CaptureCheck` test được không cần camera.
nonisolated struct CaptureMeasurements: Equatable {
    /// Bbox người hoặc vật thể, đã quy đổi sang hệ toạ độ khung hiển thị.
    var subjectRect: CGRect?
    /// Vị trí mắt của người chính (điểm giữa giữa hai mắt), hệ khung hiển thị.
    var eyePoint: CGPoint?
    /// Tư thế đầy đủ (vai/hông/gối), hệ khung hiển thị.
    ///
    /// Khác với `subjectRect`: bbox mặt chỉ cho biết **mặt ở đâu**, còn tư thế
    /// cho biết **người đang tạo dáng thế nào** — thứ quyết định ảnh có đẹp không.
    var bodyPose: BodyPose?
    /// Số người Vision nhận ra trong khung.
    var detectedPersonCount: Int = 0

    /// Tỉ lệ pixel quá sáng (0...1). Cao = cháy sáng, không lấy lại được.
    var overexposedRatio: CGFloat = 0
    /// Tỉ lệ pixel quá tối (0...1). Cao = chìm bóng.
    var underexposedRatio: CGFloat = 0
    /// Vùng trung tâm sáng hơn nền bao nhiêu. < 1 = ngược sáng.
    var centerToEdgeLuminance: CGFloat = 1
    /// Độ nét trung bình (biến thiên cục bộ trên vùng chủ thể).
    var sharpness: CGFloat = 0
    /// Độ mờ mặt: tỉ lệ độ sáng trung tâm mặt / vành quanh mặt. < 1 = có bóng.
    var faceShadowRatio: CGFloat = 1
    /// Góc nghiêng đường chân trời (độ, dương = nghiêng sang phải).
    var horizonAngle: CGFloat = 0
    /// Có nhận ra người hay không.
    var hasPerson: Bool = false
    /// Có nhận ra vật thể nổi bật hay không.
    var hasSubject: Bool = false
    /// Độ bận của nền (0...1). Cao = nền nhiều chi tiết, người dễ bị lẫn.
    var backgroundClutter: CGFloat = 0

    /// `true` khi chưa đủ dữ liệu để chấm — không nên báo "đứng sai" lúc này.
    ///
    /// - Important: `bodyPose` phải được tính vào. Người quay nghiêng mặt đi thì
    ///   Vision không thấy mặt nhưng vẫn thấy vai/hông; nếu bỏ qua nó thì app báo
    ///   "chưa nhận ra người" cho một người đang đứng ngay trước máy.
    var isEmpty: Bool {
        subjectRect == nil && !hasPerson && !hasSubject && bodyPose == nil
    }
}

// MARK: - Tiêu chí

/// Một điều kiện chất lượng ảnh.
///
/// Chia làm hai nhóm vì chúng **không cùng vai trò** — đây là điều một cách cộng
/// điểm tuyến tính đã bỏ qua:
/// - `gate`: sai thì ảnh hỏng, không kỹ thuật nào cứu được (nét, ánh sáng).
/// - `polish`: sai thì ảnh vẫn dùng được, chỉ chưa đẹp (tư thế, bố cục, nền).
nonisolated enum QualityCriterion: String, CaseIterable, Identifiable {
    case sharpness
    case lighting
    case shadow
    case horizon
    case posture
    case composition
    case background

    var id: String { rawValue }

    var isGate: Bool {
        switch self {
        case .sharpness, .lighting: true
        case .shadow, .horizon, .posture, .composition, .background: false
        }
    }

    var title: String {
        switch self {
        case .sharpness: "Lấy nét"
        case .lighting: "Ánh sáng"
        case .shadow: "Bóng trên mặt"
        case .horizon: "Nghiêng máy"
        case .posture: "Tư thế đứng"
        case .composition: "Bố cục"
        case .background: "Nền"
        }
    }

    /// Trọng số theo mode.
    ///
    /// - Important: tổng phải bằng đúng **100 trong mỗi mode**. Nếu không, mode có
    ///   ít tiêu chí hơn sẽ luôn bị trừ điểm oan. Có test ghim quy tắc này.
    ///
    ///   Nghĩa của trọng số theo tầm quan trọng nhiếp ảnh: ánh sáng và lấy nét
    ///   chiếm phần lớn vì sai hai thứ này thì ảnh hỏng không cứu được; các yếu
    ///   tố còn lại chỉ quyết định ảnh đẹp hay dở.
    func weight(for mode: CaptureMode) -> Int {
        switch (self, mode) {
        case (.sharpness, _): 25
        case (.lighting, _): 25

        case (.composition, .object): 20
        case (.composition, _): 15

        case (.posture, .object): 0
        case (.posture, _): 15

        case (.horizon, _): 10

        // Chỉ có nghĩa với khuôn mặt.
        case (.shadow, .object): 0
        case (.shadow, _): 5

        // Vật thể thì nền quan trọng hơn nhiều — tách vật khỏi nền là ưu tiên chính.
        case (.background, .object): 20
        case (.background, _): 5
        }
    }
}

// MARK: - Ngưỡng

nonisolated enum QualityThresholds {
    /// Độ nét tối thiểu. Dưới ngưỡng là ảnh mờ, không cứu được.
    static let minimumSharpness: CGFloat = 3.5

    /// Tỉ lệ pixel quá sáng cho phép.
    static let maximumOverexposed: CGFloat = 0.08
    /// Tỉ lệ pixel quá tối cho phép.
    static let maximumUnderexposed: CGFloat = 0.18

    /// Ngưỡng nghiêng máy (độ).
    static let maximumHorizonAngle: CGFloat = 1.5

    /// Ngưỡng bóng đổ trên mặt.
    static let minimumFaceLuminance: CGFloat = 0.82

    /// Chủ thể phải chiếm từ bao nhiêu phần trăm chiều cao khung (mode vật thể).
    static let minimumSubjectHeightRatio: CGFloat = 0.35
    static let maximumSubjectHeightRatio: CGFloat = 0.92

    /// Với mode người, chiều cao đầu so với chiều cao khung.
    ///
    /// Khoảng này rộng vì khuôn chỉ hướng dẫn, không ép. Người mẫu có thể đứng
    /// xa hơn một chút vẫn ra ảnh đẹp — ép quá chặt sẽ khiến app phiền.
    static let minimumHeadHeightRatio: CGFloat = 0.11
    static let maximumHeadHeightRatio: CGFloat = 0.26

    /// Độ bận nền cho phép.
    static let maximumBackgroundClutter: CGFloat = 0.35
}

// MARK: - Kết quả chấm

nonisolated enum CaptureStatus: String, Equatable {
    /// Thiếu điều kiện cần — ảnh chắc chắn xấu.
    case notReady
    /// Đã đủ điều kiện cần, còn có thể tinh chỉnh.
    case good
    /// Mọi thứ đạt.
    case ideal

    /// - `failures`: các tiêu chí gate đang fail.
    /// - `polish`: các tiêu chí còn có thể cải thiện.
    init(failures: [QualityCriterion], polish: [QualityCriterion]) {
        if failures.isEmpty {
            self = polish.isEmpty ? .ideal : .good
        } else {
            self = .notReady
        }
    }
}

nonisolated struct CriterionResult: Equatable, Identifiable {
    let criterion: QualityCriterion
    let isSatisfied: Bool
    /// Vấn đề cụ thể đã đo được, ví dụ "Nghiêng 3.2°".
    let detail: String?

    var id: String { criterion.rawValue }
}

nonisolated struct CaptureCheck: Equatable {
    let status: CaptureStatus
    let results: [CriterionResult]

    var failures: [CriterionResult] {
        results.filter { !$0.isSatisfied && $0.criterion.isGate }
    }

    var remainingPolish: [CriterionResult] {
        results.filter { !$0.isSatisfied && !$0.criterion.isGate }
    }

    var satisfied: [CriterionResult] {
        results.filter(\.isSatisfied)
    }
}

// MARK: - Chấm điểm

/// Đánh giá khung hình. **Hàm thuần** — không chạm AVFoundation hay Vision.
nonisolated enum CaptureCheckEvaluator {
    static func evaluate(
        _ measurements: CaptureMeasurements,
        mode: CaptureMode,
        template: PoseTemplate?
    ) -> CaptureCheck {
        // Chưa nhận ra gì -> không báo "đứng sai", vì có thể chỉ là ánh sáng kém.
        guard !measurements.isEmpty else {
            return CaptureCheck(status: .notReady, results: [])
        }

        let resolvedTemplate = template ?? PoseTemplate.template(for: mode)
        var results: [CriterionResult] = []

        results.append(checkSharpness(measurements))
        results.append(checkLighting(measurements))
        results.append(checkShadow(measurements, mode: mode))
        results.append(checkHorizon(measurements))
        results.append(checkPosture(measurements, mode: mode, template: resolvedTemplate))
        results.append(checkComposition(measurements, mode: mode, template: resolvedTemplate))
        results.append(checkBackground(measurements, mode: mode))

        // Bỏ tiêu chí có trọng số 0 trong mode hiện tại, và tiêu chí không đủ dữ liệu.
        let applicable = results.filter { $0.criterion.weight(for: mode) > 0 }
        let failures = applicable.filter { !$0.isSatisfied && $0.criterion.isGate }
        let polish = applicable.filter { !$0.isSatisfied && !$0.criterion.isGate }

        return CaptureCheck(status: CaptureStatus(failures: failures.map(\.criterion), polish: polish.map(\.criterion)), results: applicable)
    }

    // MARK: Gate

    private static func checkSharpness(_ m: CaptureMeasurements) -> CriterionResult {
        let ok = m.sharpness >= QualityThresholds.minimumSharpness
        return CriterionResult(
            criterion: .sharpness,
            isSatisfied: ok,
            detail: ok ? nil : String(format: "Độ nét %.1f, cần ≥ %.1f", m.sharpness, QualityThresholds.minimumSharpness)
        )
    }

    private static func checkLighting(_ m: CaptureMeasurements) -> CriterionResult {
        if m.overexposedRatio > QualityThresholds.maximumOverexposed {
            return CriterionResult(
                criterion: .lighting,
                isSatisfied: false,
                detail: String(format: "Vùng sáng bị cháy %.0f%%", m.overexposedRatio * 100)
            )
        }
        if m.underexposedRatio > QualityThresholds.maximumUnderexposed {
            return CriterionResult(
                criterion: .lighting,
                isSatisfied: false,
                detail: String(format: "Vùng tối bị chìm %.0f%%", m.underexposedRatio * 100)
            )
        }
        if m.centerToEdgeLuminance < 0.85 {
            return CriterionResult(
                criterion: .lighting,
                isSatisfied: false,
                detail: "Chủ thể tối hơn nền — đang ngược sáng"
            )
        }
        return CriterionResult(criterion: .lighting, isSatisfied: true, detail: nil)
    }

    // MARK: Polish

    private static func checkShadow(_ m: CaptureMeasurements, mode: CaptureMode) -> CriterionResult {
        // Chỉ chấm khi có mặt để so sánh, và mode người mới có nghĩa bóng mặt.
        guard mode.usesBodyTemplate, m.hasPerson, m.eyePoint != nil else {
            return CriterionResult(criterion: .shadow, isSatisfied: true, detail: nil)
        }
        let ok = m.faceShadowRatio >= QualityThresholds.minimumFaceLuminance
        return CriterionResult(
            criterion: .shadow,
            isSatisfied: ok,
            detail: ok ? nil : "Mặt tối hơn xung quanh — đang có bóng đổ"
        )
    }

    private static func checkHorizon(_ m: CaptureMeasurements) -> CriterionResult {
        let magnitude = abs(m.horizonAngle)
        let ok = magnitude <= QualityThresholds.maximumHorizonAngle
        return CriterionResult(
            criterion: .horizon,
            isSatisfied: ok,
            detail: ok ? nil : String(format: "Nghiêng %.1f°, cần ≤ %.1f°", magnitude, QualityThresholds.maximumHorizonAngle)
        )
    }

    private static func checkPosture(
        _ m: CaptureMeasurements,
        mode: CaptureMode,
        template: PoseTemplate?
    ) -> CriterionResult {
        // Vật thể không có tư thế đứng.
        guard mode.usesBodyTemplate else {
            return CriterionResult(criterion: .posture, isSatisfied: true, detail: nil)
        }
        guard m.hasPerson else {
            return CriterionResult(criterion: .posture, isSatisfied: false, detail: "Chưa nhận ra người trong khung")
        }
        guard let template else {
            return CriterionResult(criterion: .posture, isSatisfied: true, detail: nil)
        }

        // Mắt phải nằm gần đường mắt của khuôn, tính theo chiều cao đầu.
        if let eye = m.eyePoint {
            let deviation = abs(eye.y - template.eyeLineRatio)
            if deviation > template.headTolerance {
                let direction = eye.y < template.eyeLineRatio ? "lên" : "xuống"
                return CriterionResult(
                    criterion: .posture,
                    isSatisfied: false,
                    detail: String(format: "Mắt lệch %.1f%% chiều cao khung so với đường 1/3", deviation * 100)
                        + " (đang \(eye.y < template.eyeLineRatio ? "thấp" : "cao") hơn khuôn)"
                        + " — hãy đứng \(direction) cho đúng đường"
                )
            }
        }

        // Đầu không được tràn lên khung.
        if let rect = m.subjectRect, rect.minY < -template.topHeadSlack {
            return CriterionResult(
                criterion: .posture,
                isSatisfied: false,
                detail: "Đỉnh đầu đã bị cắt — lùi ra xa một chút"
            )
        }

        // Tâm người lệch quá nhiều so với khuôn.
        if let rect = m.subjectRect {
            let centerOffset = abs(rect.midX - 0.5)
            if centerOffset > 0.5 * template.shoulderWidthRatio + template.horizontalSlack {
                let direction = rect.midX < 0.5 ? "sang trái" : "sang phải"
                return CriterionResult(
                    criterion: .posture,
                    isSatisfied: false,
                    detail: "Tâm người lệch \(direction) khỏi tâm khuôn"
                )
            }
        }

        return CriterionResult(criterion: .posture, isSatisfied: true, detail: nil)
    }

    private static func checkComposition(
        _ m: CaptureMeasurements,
        mode: CaptureMode,
        template: PoseTemplate?
    ) -> CriterionResult {
        // Số người phải khớp mode (nếu mode có yêu cầu).
        if let expected = mode.expectedSubjectCount {
            let actual = m.detectedPersonCount
            if actual != expected {
                return CriterionResult(
                    criterion: .composition,
                    isSatisfied: false,
                    detail: "Cần \(expected) người nhưng đang có \(actual)"
                )
            }
        }

        guard let rect = m.subjectRect else {
            return CriterionResult(
                criterion: .composition,
                isSatisfied: false,
                detail: "Chưa nhận ra chủ thể trong khung"
            )
        }

        // Với mode người, `subjectRect` là **bbox khuôn mặt** (Vision chỉ trả về
        // mặt), nên phải so với chiều cao đầu của khuôn chứ không so với chiều
        // cao thân — nếu không sẽ bắt người mẫu đứng sát ống kính mới đạt.
        if mode.usesBodyTemplate, let template {
            return checkHeadScale(faceHeight: rect.height, template: template)
        }

        // Mode vật thể: chủ thể phải đủ lớn nhưng không sát mép.
        let heightRatio = rect.height
        if heightRatio < QualityThresholds.minimumSubjectHeightRatio {
            return CriterionResult(
                criterion: .composition,
                isSatisfied: false,
                detail: "Vật thể chiếm \(Int(heightRatio * 100))% chiều cao khung — hãy tiến lại gần hơn"
            )
        }
        if heightRatio > QualityThresholds.maximumSubjectHeightRatio {
            return CriterionResult(
                criterion: .composition,
                isSatisfied: false,
                detail: "Vật thể chiếm \(Int(heightRatio * 100))% chiều cao khung — hãy lùi xa hơn"
            )
        }

        return CriterionResult(criterion: .composition, isSatisfied: true, detail: nil)
        }

        /// So chiều cao bbox mặt với chiều cao đầu mà khuôn quy định.
        private static func checkHeadScale(
        faceHeight: CGFloat,
        template: PoseTemplate
        ) -> CriterionResult {
        // Vision trả bbox mặt từ chân tóc tới cằm, tức khoảng 0.75 chiều cao
        // đầu (phần đỉnh đầu bị tóc che nên không có trong bbox).
        let faceToHeadRatio: CGFloat = 0.75
        let expectedFaceHeight = template.headHeightRatio * faceToHeadRatio
        let actualHeadHeight = faceHeight / faceToHeadRatio

        if actualHeadHeight < QualityThresholds.minimumHeadHeightRatio {
            return CriterionResult(
                criterion: .composition,
                isSatisfied: false,
                detail: "Đầu nhỏ hơn khuôn một chút — hãy tiến lại gần hơn"
            )
        }
        if actualHeadHeight > QualityThresholds.maximumHeadHeightRatio {
            return CriterionResult(
                criterion: .composition,
                isSatisfied: false,
                detail: "Đầu lớn hơn khuôn — hãy lùi xa hơn một chút"
            )
        }
        _ = expectedFaceHeight

        return CriterionResult(criterion: .composition, isSatisfied: true, detail: nil)
        }

        private static func checkBackground(_ m: CaptureMeasurements, mode: CaptureMode) -> CriterionResult {
        guard m.hasSubject else {
            return CriterionResult(criterion: .background, isSatisfied: true, detail: nil)
        }
        let ok = m.backgroundClutter <= QualityThresholds.maximumBackgroundClutter
        return CriterionResult(
            criterion: .background,
            isSatisfied: ok,
            detail: ok ? nil : String(format: "Nền nhiều chi tiết (%.0f%%) — người dễ bị lẫn vào nền", m.backgroundClutter * 100)
        )
    }
}
