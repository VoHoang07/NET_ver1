import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Dựng hình học người và bàn ghề từ hình khối.
///
/// ## Vì sao dựng bằng code thay vì dùng file `.usdz`
///
/// Tôi không tạo được file 3D có xương và animation. Hình khối làm được những gì
/// brief cần mà không cần asset: đúng tỉ lệ người thật, đổi tư thế theo yêu cầu,
/// và — quan trọng nhất — **biến mất được** khi người thật che khuất.
///
/// Khi nào bạn có file `.usdz`, chỉ cần thay phần thân trong `makeFigure` và phần
/// thân trong `makeTable`. Phần đặt trong không gian, chọn API, vật liệu giữ nguyên.
///
/// ## Vì sao không có mặt
///
/// Người mẫu so sánh mặt mình với mặt bóng — và bao giờ cũng thua. Đầu trơn không
/// ai so sánh được, mà vẫn truyền đủ thông tin về hướng đầu.

// MARK: - Dựng hình học

/// Dựng người từ hình khối theo đúng nhân thân chuẩn.
/// - Important: `Entity` là `@MainActor`, nên toàn bộ phần dựng hình học phải
///   ở main actor.
@MainActor
enum FigureBuilder {

    /// Màu ảo — cam để dễ phân biệt với người thật khi đang hướng dẫn.
    nonisolated static let color: UIColor = UIColor(
        red: 1.0, green: 0.45, blue: 0.2, alpha: 1
    )

    /// Người 3D hoàn chỉnh, gốc tại **mặt đất** (Y = 0).
    static func makeFigure(pose: ShootingPose, metrics: FigureMetrics) -> Entity {
        let root = Entity()
        let h = metrics.headHeight

        // Các kích thước quy từ chiều cao đầu sang mét rồi nhân thêm `h`.
        func wide(_ ratio: CGFloat) -> Float { Float(ratio * h) }
        /// Chiều cao khối = khoảng cách giữa hai mốc, tính bằng mét.
        func tall(_ top: CGFloat, _ bottom: CGFloat) -> Float {
            Float((top - bottom) * h)
        }

        // --- Thân ---
        let chest = box(
            width: wide(FigureBuild.Width.shoulder * 0.86),
            height: tall(FigureBuild.Heads.chest, FigureBuild.Heads.waist),
            depth: wide(FigureBuild.Width.depth),
            bottomInHeads: FigureBuild.Heads.waist,
            metrics: metrics
        )
        let abdomen = box(
            width: wide(FigureBuild.Width.waist),
            height: tall(FigureBuild.Heads.waist, FigureBuild.Heads.hip),
            depth: wide(FigureBuild.Width.depth * 0.9),
            bottomInHeads: FigureBuild.Heads.hip,
            metrics: metrics
        )
        root.addChild(chest)
        root.addChild(abdomen)

        // --- Đầu ---
        let head = sphere(
            diameter: wide(FigureBuild.Width.head),
            at: FigureBuild.Heads.eyeLine,
            metrics: metrics
        )
        root.addChild(head)

        // Cổ nối đầu với thân, không để lệch khi quay đầu.
        let neck = box(
            width: wide(0.3),
            height: tall(FigureBuild.Heads.chin, FigureBuild.Heads.shoulder),
            depth: wide(0.3),
            bottomInHeads: FigureBuild.Heads.shoulder,
            metrics: metrics
        )
        root.addChild(neck)

        // --- Cánh tay ---
        addArms(to: root, pose: pose, metrics: metrics, h: h, wide: wide, tall: tall)

        // --- Chân ---
        if pose.stance == .standing {
            addLegs(to: root, metrics: metrics, h: h, wide: wide, tall: tall)
        }

        return root
    }

    /// Nghiêng vai và xoay thân theo tư thế đã chọn.
    ///
    /// - Important: xoay quanh trục **Z** để vai lệch cân — quanh trục khác thì người
    ///   bị nghiêng ngang như bị gãy.
    private static func addArms(
        to root: Entity,
        pose: ShootingPose,
        metrics: FigureMetrics,
        h: CGFloat,
        wide: (CGFloat) -> Float,
        tall: (CGFloat, CGFloat) -> Float
    ) {
        let shoulderY = tall(FigureBuild.Heads.shoulder, FigureBuild.Heads.shoulder)
        let armLength = tall(FigureBuild.Heads.shoulder, FigureBuild.Heads.hip)
        let shoulderX = wide(FigureBuild.Width.shoulder) / 2
        let tilt = metrics.shoulderRoll * .pi / 180

        for side in [-1.0, 1.0] as [Float] {
            let arm = box(
                width: wide(0.42),
                height: armLength,
                depth: wide(0.42),
                bottomInHeads: FigureBuild.Heads.shoulder,
                metrics: metrics
            )

            // Khi ngồi, tay chống lên bàn nên ngắn lại và chĩa ra trước.
            let forward: Float = metrics.armsRestOnTable ? wide(0.9) : 0
            arm.position = SIMD3(
                side * shoulderX + forward,
                shoulderY - armLength / 2 + Float(sin(tilt)) * shoulderX,
                -forward * 0.5
            )
            arm.orientation = simd_quatf(angle: Float(tilt) * side, axis: SIMD3(0, 0, 1))
            root.addChild(arm)
        }
    }

    private static func addLegs(
        to root: Entity,
        metrics: FigureMetrics,
        h: CGFloat,
        wide: (CGFloat) -> Float,
        tall: (CGFloat, CGFloat) -> Float
    ) {
        let legLength = tall(FigureBuild.Heads.hip, FigureBuild.Heads.ankle)
        let hipX = wide(FigureBuild.Width.hip) / 4

        for side in [-1.0, 1.0] as [Float] {
            let leg = box(
                width: wide(0.5),
                height: legLength,
                depth: wide(0.5),
                bottomInHeads: FigureBuild.Heads.hip,
                metrics: metrics
            )
            leg.position = SIMD3(
                side * hipX,
                legLength / 2,
                0
            )
            root.addChild(leg)
        }
    }

    // MARK: - Hình khối

    /// Một hình hộp, **đáy** đặt tại mốc `bottomInHeads`.
    ///
    /// - Parameters:
    ///   - bottomInHeads: **mốc đáy** tính bằng số đầu, đo từ đỉnh đầu xuống.
    ///     Khốp đáy với mốc này để khối nằm đúng chỗ trên cơ thể.
    ///   - metrics: quy đổi số đầu sang mét và đặt Y theo mặt đất.
    private static func box(
        width: Float,
        height: Float,
        depth: Float,
        bottomInHeads: CGFloat,
        metrics: FigureMetrics
    ) -> Entity {
        let mesh = MeshResource.generateBox(
            size: SIMD3(width, height, depth),
            cornerRadius: min(width, height, depth) * 0.28
        )
        let entity = ModelEntity(mesh: mesh, materials: [])
        entity.position = metrics.position(of: bottomInHeads)
        return entity
    }

    /// Đầu: khối cầu, tâm đặt ở đường mắt.
    ///
    /// - Important: `generateSphere` tạo cầu **bán kính** `radius` — đường kính
    ///   là 2×. Tâm cầu đặt ở đường mắt, không phải đỉnh đầu, nên khi đo bằng
    ///   "số đầu" thì tâm phải ở 1.0 đầu tính từ đỉnh.
    private static func sphere(
        diameter: Float,
        at heightInHeads: CGFloat,
        metrics: FigureMetrics
    ) -> Entity {
        let mesh = MeshResource.generateSphere(radius: diameter / 2)
        let entity = ModelEntity(mesh: mesh, materials: [])
        entity.position = metrics.position(of: heightInHeads)
        return entity
    }
}
