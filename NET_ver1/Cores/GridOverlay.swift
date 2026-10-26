import SwiftUI

/// Lưới bố cục 1/3 (Rule of Thirds) chuẩn máy ảnh chuyên nghiệp:
/// Nét siêu mảnh (`0.6pt`), độ mờ tinh tế (`32%` trắng) kèm dấu tâm giao điểm 1/3.
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let x1 = width / 3
            let x2 = (width / 3) * 2
            let y1 = height / 3
            let y2 = (height / 3) * 2
            let crossArm: CGFloat = 5

            ZStack {
                Path { path in
                    // Đường dọc 1/3 và 2/3
                    path.move(to: CGPoint(x: x1, y: 0))
                    path.addLine(to: CGPoint(x: x1, y: height))

                    path.move(to: CGPoint(x: x2, y: 0))
                    path.addLine(to: CGPoint(x: x2, y: height))

                    // Đường ngang 1/3 và 2/3
                    path.move(to: CGPoint(x: 0, y: y1))
                    path.addLine(to: CGPoint(x: width, y: y1))

                    path.move(to: CGPoint(x: 0, y: y2))
                    path.addLine(to: CGPoint(x: width, y: y2))
                }
                .stroke(Color.white.opacity(0.32), lineWidth: 0.6)

                // Dấu cộng tinh tế tại 4 giao điểm vàng (Rule of Thirds Intersections)
                Path { path in
                    for ix in [x1, x2] {
                        for iy in [y1, y2] {
                            path.move(to: CGPoint(x: ix - crossArm, y: iy))
                            path.addLine(to: CGPoint(x: ix + crossArm, y: iy))
                            path.move(to: CGPoint(x: ix, y: iy - crossArm))
                            path.addLine(to: CGPoint(x: ix, y: iy + crossArm))
                        }
                    }
                }
                .stroke(Color.white.opacity(0.55), lineWidth: 1.0)
            }
        }
        .allowsHitTesting(false)
    }
}
