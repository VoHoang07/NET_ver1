import CoreGraphics
import Foundation
import RealityKit

/// Bàn và ghế ảo cho tư thế ngồi.
///
/// ## Vì sao cần khớp bàn thật
///
/// Ngồi lệch so với bàn thật thì tạo dáng không tự nhiên — tay không chạm mặt
/// bàn, chân không đặt dưới bàn. Đây là lý do người dùng phải nhập chiều cao:
/// không có nó thì app không biết bàn cao bao nhiêu.
///
/// ## Vì sao tính bằng "số đầu"
///
/// Cùng lý do với người: dùng một đơn vị chung để bàn ghế và người luôn cùng tỉ lệ.
/// Đổi sang mét ở đúng một chỗ là `metrics.headHeight`.
/// - Important: `Entity` là `@MainActor`, nên toàn bộ phần dựng hình học phải
///   ở main actor.
@MainActor
enum FurnitureBuilder {

    /// Chiều cao mặt bàn, tính bằng số đầu, đo từ mặt đất lên.
    ///
    /// - Important: đây là **quy ước tạm**, chưa phải số đo thật. Người cao 1,70m
    ///   thì 1,7 đầu ≈ 0,39m — thấp hơn bàn ăn thông thường (~0,75m). Số này sẽ
    ///   thay bằng số đo từ quét phòng; tới lúc đó đừng tinh chỉnh con số ở đây.
    static let tableHeightInHeads: CGFloat = 3.2
    /// Bề rộng mặt bàn, tính bằng số đầu.
    static let tableWidthInHeads: CGFloat = 4.4
    /// Chiều sâu mặt bàn, tính bằng số đầu.
    static let tableDepthInHeads: CGFloat = 2.6
    /// Độ dày mặt bàn.
    static let tableThicknessInHeads: CGFloat = 0.14

    /// Mặt bàn + ghế, gốc tại **mặt đất** (Y = 0).
    static func makeTable(metrics: FigureMetrics) -> Entity {
        let root = Entity()
        let h = metrics.headHeight

        // Mặt bàn: đáy đặt ngay dưới mặt bàn.
        let top = ModelEntity(
            mesh: .generateBox(
                size: SIMD3(
                    Float(tableWidthInHeads * h),
                    Float(tableThicknessInHeads * h),
                    Float(tableDepthInHeads * h)
                ),
                cornerRadius: Float(0.06 * h)
            ),
            materials: []
        )
        top.position.y = Float((tableHeightInHeads - tableThicknessInHeads) * h)
        root.addChild(top)

        // Ghế đặt **sau** bàn (xa camera hơn), vì người mẫu ngồi sau bàn.
        let seatHeightInHeads = tableHeightInHeads - 1.2
        let seat = ModelEntity(
            mesh: .generateBox(
                size: SIMD3(Float(1.8 * h), Float(0.16 * h), Float(1.8 * h)),
                cornerRadius: Float(0.06 * h)
            ),
            materials: []
        )
        seat.position = SIMD3(0, Float(seatHeightInHeads * h), Float(1.0 * h))
        root.addChild(seat)

        let backRest = ModelEntity(
            mesh: .generateBox(
                size: SIMD3(Float(1.8 * h), Float(2.0 * h), Float(0.16 * h)),
                cornerRadius: Float(0.06 * h)
            ),
            materials: []
        )
        backRest.position = SIMD3(0, Float((seatHeightInHeads + 1.0) * h), Float(1.9 * h))
        root.addChild(backRest)

        return root
    }
}