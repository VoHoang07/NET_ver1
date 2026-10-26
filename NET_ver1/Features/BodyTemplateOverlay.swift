import SwiftUI

/// Bóng người mờ, vẽ đúng tư thế người dùng đã chọn.
///
/// ## Vì sao mờ
///
/// Người thật ở đúng chỗ sẽ **che bóng người này**, và khi khớp thì bóng biến mất
/// hẳn. Đó là chủ ý — không gì trên màn hình khi đã chụp được.
///
/// Mờ vừa, không quá mờ: quá mờ thì người mẫu không nhìn ra mình phải đứng đâu.
///
/// ## Vì sao không có chi tiết mặt
///
/// Nếu có mặt, người mẫu so sánh mặt mình với mặt bóng — và bao giờ cũng thua.
/// Đầu trơn không ai so sánh được, mà vẫn truyền đủ thông tin về hướng đầu.
struct GuideFigure: View {
    let pose: ShootingPose
    let layout: SceneComposer.Layout?
    /// Đã khớp chưa — khi khớp thì bóng mờ dần thay vì biến mất ngột.
    let isAligned: Bool
    /// Tiến độ chờ chụp tự động (0...1).
    let autoProgress: CGFloat

    private var accent: Color {
        isAligned ? .netGreen : .netCoral
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(pose: pose, layout: layout, size: proxy.size)

            ZStack {
                ZStack {
                    bodyShape(metrics)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.30), accent.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    bodyShape(metrics)
                        .stroke(
                            accent.opacity(0.85),
                            style: .init(lineWidth: 2, lineJoin: .round)
                        )
                }

                if pose.usesTable {
                    tableShape(metrics)
                        .fill(accent.opacity(0.10))
                        .stroke(accent.opacity(0.55), style: .init(lineWidth: 1.5))
                }

                if autoProgress > 0 {
                    countdownShape(metrics)
                        .stroke(
                            Color.netGreen,
                            style: .init(lineWidth: 3, lineCap: .round)
                        )
                }
            }
            .animation(.easeOut(duration: 0.35), value: isAligned)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Thân

    private func bodyShape(_ m: Metrics) -> Path {
        var path = Path()

        // Đầu — trơn, không có chi tiết mặt.
        path.addEllipse(in: CGRect(
            x: m.headCenter.x - m.headRadius,
            y: m.headCenter.y - m.headRadius,
            width: m.headRadius * 2,
            height: m.headRadius * 2
        ))

        // Cổ nối đầu với thân.
        path.move(to: m.neckLeft)
        path.addLine(to: m.neckRight)

        // Thân: từ vai xuống hông.
        path.move(to: m.shoulderLeft)
        path.addLine(to: m.shoulderRight)
        path.addLine(to: m.hipRight)
        path.addQuadCurve(
            to: m.hipLeft,
            control: CGPoint(x: m.hipRight.x, y: m.hipRight.y + m.hipRound)
        )
        path.addLine(to: m.shoulderLeft)
        path.closeSubpath()

        // Cánh tay. Khi ngồi phải nối vai → khuỷu → tay; thiếu đoạn vai → khuỷu thì
        // cánh tay bị đứt, nhìn như người mất tay.
        if pose.stance == .seated {
            path.move(to: m.armStartLeft)
            path.addLine(to: m.elbowLeft)
            path.addLine(to: m.handLeft)
            path.move(to: m.armStartRight)
            path.addLine(to: m.elbowRight)
            path.addLine(to: m.handRight)
        } else {
            path.move(to: m.armStartLeft)
            path.addLine(to: m.handLeft)
            path.move(to: m.armStartRight)
            path.addLine(to: m.handRight)
        }

        return path
    }

    /// Bàn ảo — chỉ vẽ khi tư thế ngồi.
    private func tableShape(_ m: Metrics) -> Path {
        var path = Path()
        path.move(to: m.tableLeft)
        path.addLine(to: m.tableRight)
        path.addLine(to: m.tableRightCorner)
        path.addLine(to: m.tableLeftCorner)
        path.closeSubpath()
        return path
    }

    /// Vòng tròn đếm ngược trước khi bấm.
    private func countdownShape(_ m: Metrics) -> Path {
        var path = Path()
        let r = m.headRadius * 1.6
        path.addArc(
            center: m.headCenter,
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(max(autoProgress, 0), 1)),
            clockwise: false
        )
        return path
    }
}

// MARK: - Số đo

/// Quy đổi tư thế + bố cục sang toạ độ thực trong khung.
private struct Metrics {
    let headCenter: CGPoint
    let headRadius: CGFloat
    let neckLeft: CGPoint
    let neckRight: CGPoint
    let shoulderLeft: CGPoint
    let shoulderRight: CGPoint
    let hipLeft: CGPoint
    let hipRight: CGPoint
    let elbowLeft: CGPoint
    let elbowRight: CGPoint
    let armStartLeft: CGPoint
    let armStartRight: CGPoint
    let handLeft: CGPoint
    let handRight: CGPoint
    let tableLeft: CGPoint
    let tableRight: CGPoint
    let tableLeftCorner: CGPoint
    let tableRightCorner: CGPoint
    let hipRound: CGFloat

    init(pose: ShootingPose, layout: SceneComposer.Layout?, size: CGSize) {
        // Kích thước lấy từ `Layout` nếu có; nếu không thì dùng tỉ lệ chuẩn.
        let widthRatio = layout?.subjectWidthRatio ?? 0.44
        let headRatio = layout?.headHeightRatio ?? pose.headHeightRatio

        let shoulderWidth = widthRatio * size.width
        let headHeight = headRatio * size.height
        let half = shoulderWidth / 2
        let centerX = size.width / 2
        let centerY = (layout?.subjectCenter.y ?? 0.48) * size.height

        let headRadius = headHeight * BodyCanon.Width.head / 2
        let headY = centerY - headHeight * 1.5
        let headCenter = CGPoint(x: centerX, y: headY)
        self.headCenter = headCenter
        self.headRadius = headRadius

        // Cổ nằm giữa đầu và vai.
        let neckY = headY + headRadius * 1.5
        let neckHalf = headRadius * 0.34
        neckLeft = CGPoint(x: centerX - neckHalf, y: neckY)
        neckRight = CGPoint(x: centerX + neckHalf, y: neckY)

        // Vai nghiêng theo tư thế đã chọn.
        let shoulderY = neckY + headHeight * 0.75
        let tiltRad = pose.shoulderTilt * .pi / 180
        let tiltDrop = half * tan(tiltRad)
        shoulderLeft = CGPoint(x: centerX - half, y: shoulderY - tiltDrop / 2)
        shoulderRight = CGPoint(x: centerX + half, y: shoulderY + tiltDrop / 2)

        // Thân nghiêng theo trục; hông hẹp hơn vai theo nhân thân chuẩn.
        let hipHalf = half * (BodyCanon.Width.hip / BodyCanon.Width.shoulder)
        let torsoLength = headHeight * 2.5
        let spineRad = pose.spineTilt * .pi / 180
        let spineShift = torsoLength * sin(spineRad)
        let hipY = shoulderY + torsoLength * cos(spineRad)
        hipLeft = CGPoint(x: centerX - hipHalf + spineShift, y: hipY)
        hipRight = CGPoint(x: centerX + hipHalf + spineShift, y: hipY)
        hipRound = hipHalf * 0.3

        // Cánh tay.
        let armInset = headHeight * 0.2
        armStartLeft = CGPoint(x: shoulderLeft.x, y: shoulderLeft.y + armInset)
        armStartRight = CGPoint(x: shoulderRight.x, y: shoulderRight.y + armInset)

        let isSeated = pose.stance == .seated
        let elbowSpread: CGFloat = isSeated ? 0.72 : 0.9
        let handSpread: CGFloat = isSeated ? 0.55 : 0.95
        let handY = isSeated ? hipY + headHeight * 0.55 : hipY + headHeight * 1.9

        elbowLeft = CGPoint(x: centerX - half * elbowSpread, y: hipY - headHeight * 0.1)
        elbowRight = CGPoint(x: centerX + half * elbowSpread, y: hipY - headHeight * 0.1)
        handLeft = CGPoint(x: centerX - half * handSpread, y: handY)
        handRight = CGPoint(x: centerX + half * handSpread, y: handY)

        // Bàn: mặt bàn nằm ngang tay, rộng hơn thân một chút.
        tableLeft = CGPoint(x: centerX - half * 1.5, y: handY)
        tableRight = CGPoint(x: centerX + half * 1.5, y: handY)
        tableLeftCorner = CGPoint(x: centerX - half * 1.5, y: handY + headHeight * 0.5)
        tableRightCorner = CGPoint(x: centerX + half * 1.5, y: handY + headHeight * 0.5)
    }
}