import CoreGraphics
import Foundation

/// Tư thế người, đo bằng `VNDetectHumanBodyPoseRequest`.
///
/// ## Vì sao cần lớp này
///
/// Trước đây app chỉ đo được **mặt** (`VNDetectFaceRectanglesRequest`). Nhưng để
/// biết người mẫu có đang tạo dáng đúng không thì phải đo **vai, hông, gối** —
/// không có thì app chỉ hướng dẫn chứ không chấm được.
///
/// ## Hệ toạ độ
///
/// Giữ nguyên hệ của Vision: chuẩn hoá 0...1, gốc **đáy-trái**, trục Y hướng lên.
/// Giữ nguyên để không phải đổi toạ độ hai lần — `SafeArea` đã lo việc quy đổi
/// sang khung hiển thị.
nonisolated struct BodyPose: Equatable, Sendable {
    /// Các mốc cơ thể Vision trả về. `nil` nghĩa là Vision không thấy mốc đó —
    /// thường do bị che hoặc ngoài khung.
    nonisolated struct Joints: Equatable, Sendable {
        var nose: CGPoint?
        var neck: CGPoint?
        var leftShoulder: CGPoint?
        var rightShoulder: CGPoint?
        var leftElbow: CGPoint?
        var rightElbow: CGPoint?
        var leftWrist: CGPoint?
        var rightWrist: CGPoint?
        var leftHip: CGPoint?
        var rightHip: CGPoint?
        var leftKnee: CGPoint?
        var rightKnee: CGPoint?
        var leftAnkle: CGPoint?
        var rightAnkle: CGPoint?

        /// Các mốc Vision đảm bảo đo được: thiếu một trong ba thì bỏ qua cả
        /// khung hình, vì tư thế mà thiếu vai hoặc hông thì không chấm được.
        var hasTorso: Bool {
            leftShoulder != nil && rightShoulder != nil && leftHip != nil && rightHip != nil
        }
    }

    var joints: Joints

    // MARK: - Mốc dẫn xuất

    var shoulderMid: CGPoint? {
        Self.midpoint(joints.leftShoulder, joints.rightShoulder)
    }

    var hipMid: CGPoint? {
        Self.midpoint(joints.leftHip, joints.rightHip)
    }

    /// Đầu: ưu tiên mũi, thiếu thì dùng cổ làm đại diện.
    var headCenter: CGPoint? {
        joints.nose ?? joints.neck
    }

    var kneeMid: CGPoint? {
        Self.midpoint(joints.leftKnee, joints.rightKnee)
    }

    var ankleMid: CGPoint? {
        Self.midpoint(joints.leftAnkle, joints.rightAnkle)
    }

    var wristMid: CGPoint? {
        Self.midpoint(joints.leftWrist, joints.rightWrist)
    }

    /// Bề ngang vai, chuẩn hoá theo chiều ngang khung.
    var shoulderWidth: CGFloat? {
        guard let a = joints.leftShoulder, let b = joints.rightShoulder else { return nil }
        return abs(b.x - a.x)
    }

    /// Chiều dài thân (vai → hông) — đơn vị so sánh, không phải pixel thật.
    var torsoLength: CGFloat? {
        guard let a = shoulderMid, let b = hipMid else { return nil }
        return hypot(b.x - a.x, b.y - a.y)
    }

    /// Chiều cao đầu ước lượng từ khoảng cách cổ → mũi.
    ///
    /// Dùng để so kích thước người với khuôn, thay cho bbox mặt — bbox mặt chỉ
    /// phủ từ chân tóc tới cằm, còn cổ → mũi ổn định hơn khi người mẫu cúi đầu.
    var estimatedHeadHeight: CGFloat? {
        guard let neck = joints.neck, let nose = joints.nose else { return nil }
        return hypot(nose.x - neck.x, nose.y - neck.y)
    }

    /// Góc nghiêng vai (độ). Dương = vai **phải thấp hơn** vai trái.
    ///
    /// Người đứng thẳng có vai gần bằng; nghiêng người tạo dáng thì vai lệch, và
    /// đó là thứ cho ảnh có chiều sâu chứ không phải lỗi.
    var shoulderTiltDegrees: CGFloat? {
        guard let a = joints.leftShoulder, let b = joints.rightShoulder, a.x != b.x else { return nil }
        // Vision: Y hướng lên, X hướng phải.
        let rise = b.y - a.y
        let run = b.x - a.x
        return atan2(rise, abs(run)) * 180 / .pi
    }

    /// Góc lệch của trục thân so với thẳng đứng (độ). Dương = nghiêng sang phải.
    var spineTiltDegrees: CGFloat? {
        guard let shoulder = shoulderMid, let hip = hipMid else { return nil }
        let dx = shoulder.x - hip.x
        // Thân nghiêng càng nhiều khi |dx| lớn so với chiều dài thân.
        let ratio = dx / max(torsoLength ?? 1, 0.0001)
        return asin(max(-1, min(1, ratio))) * 180 / .pi
    }

    /// Mức độ duỗi chân (1 = đứng thẳng, nhỏ = ngồi/khúm).
    ///
    /// - Important: đây là **ước lượng**, không phải đo chắc. Góc nhìn từ trên
    ///   làm méo tỉ lệ này. Vì người dùng **chọn tư thế trước**, ta không dùng
    ///   giá trị này để quyết định — chỉ để báo gợi ý.
    var legExtension: CGFloat? {
        guard let hip = hipMid, let ankle = ankleMid, let torso = torsoLength, torso > 0 else {
            return nil
        }
        let drop = ankle.y - hip.y
        return drop / torso
    }

    /// Bbox bao toàn bộ mốc nhìn thấy.
    var boundingBox: CGRect? {
        let points: [CGPoint] = [
            joints.nose, joints.neck,
            joints.leftShoulder, joints.rightShoulder,
            joints.leftElbow, joints.rightElbow,
            joints.leftWrist, joints.rightWrist,
            joints.leftHip, joints.rightHip,
            joints.leftKnee, joints.rightKnee,
            joints.leftAnkle, joints.rightAnkle,
        ].compactMap { $0 }

        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `true` khi đủ dữ liệu để chấm tư thế.
    var isUsable: Bool {
        joints.hasTorso && headCenter != nil
    }

    // MARK: - Tiện ích

    private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a, let b else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}