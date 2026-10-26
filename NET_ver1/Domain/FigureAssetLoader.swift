import CoreGraphics
import Foundation
import RealityKit

/// Tải người 3D từ file `.usdz` thay vì dựng bằng hình khối.
///
/// ## Vì sao mỗi tạo dáng một file
///
/// RealityKit không đọc được nhiều animation trong một USDZ. Theo đặc tả USD,
/// `SkelRoot` chỉ giữ **một** quan hệ `skel:animationSource` tới `SkelAnimation`,
/// và RealityKit đọc animation **qua đúng quan hệ đó**. Ghép 6 clip vào một file
/// thì file vẫn hợp lệ, `usdcat` đọc bình thường, tên cả 6 clip đều hiện — nhưng
/// `availableAnimations` trả về **rỗng**.
///
/// Đó là kiểu lỗi im lặng nguy hiểm nhất: build sạch, test khác xanh, không log
/// lỗi nào, chỉ có tạo dáng sai.
///
/// Nên `tools/bake_poses.py` **nướng** từng tạo dáng thành mesh tĩnh: không còn
/// xương, không còn animation, luôn hiển thị đúng. Đúng brief: người 3D đứng yên,
/// không tự chuyển động.
///
/// ## Fallback
///
/// Thiếu file hoặc load lỗi thì `load()` trả `nil` và `GuideSceneBuilder` dùng
/// hình khối. App không bao giờ trắng màn hình vì lý do asset.
enum FigureAssetLoader {

    /// Tên file cho một tạo dáng: `pose.id` → `"pose-" + id + ".usdz"`.
    ///
    /// - Important: `Bundle.main.url(forResource:withExtension:)` cần tên **không**
    ///   kèm đuôi. Đặt nhầm thành `"pose-seated-straight.usdz"` sẽ tìm thành
    ///   `"pose-seated-straight.usdz.usdz"` và luôn trả `nil` — lỗi dễ mắc mà khó
    ///   phát hiện, vì code chỉ đơn giản rơi về hình khối.
    nonisolated static func resourceName(for poseID: String) -> String {
        "pose-\(poseID)"
    }

    /// Có file của tạo dáng này trong bundle không.
    nonisolated static func isAvailable(for pose: ShootingPose) -> Bool {
        Bundle.main.url(
            forResource: resourceName(for: pose.id),
            withExtension: "usdz"
        ) != nil
    }

    /// Bộ đệm nguyên mẫu (prototype cache) trong RAM cho các file `.usdz` đã đọc từ đĩa.
    /// Khi chuyển tư thế, ứng dụng chỉ cần nhân bản (`clone(recursive: true)`) từ nguyên mẫu
    /// trong bộ nhớ (< 1ms) thay vì đọc và giải mã lại file USDZ đồng bộ trên Main Thread.
    @MainActor
    private static var prototypeCache: [URL: Entity] = [:]

    /// Giải phóng bộ đệm nguyên mẫu khi cần thu hồi bộ nhớ.
    @MainActor
    static func clearCache() {
        prototypeCache.removeAll()
    }

    /// Nạp đồng bộ 1 tư thế vào `prototypeCache` (tách hàm non-async để tránh cảnh báo Swift 6).
    @MainActor
    private static func preloadPoseIfNeeded(_ pose: ShootingPose, bundle: Bundle) {
        guard let url = bundle.url(
            forResource: resourceName(for: pose.id),
            withExtension: "usdz"
        ) else { return }
        if prototypeCache[url] == nil, let prototype = try? Entity.load(contentsOf: url) {
            prototypeCache[url] = prototype
        }
    }

    /// Nạp trước dần dần cả 6 tư thế vào `prototypeCache` ở các nhịp nghỉ sau khi mở app,
    /// giúp thao tác bấm chuyển tư thế lần đầu phản hồi tức thì mà không làm nghẽn lúc khởi động.
    @MainActor
    static func warmUpPosesGradually(bundle: Bundle = .main) async {
        try? await Task.sleep(for: .milliseconds(450))
        for pose in ShootingPose.all {
            preloadPoseIfNeeded(pose, bundle: bundle)
            try? await Task.sleep(for: .milliseconds(70))
        }
    }

    /// Tải người ở đúng tạo dáng, chuẩn hoá tỉ lệ theo chiều cao người mẫu.
    ///
    /// - Returns: `nil` khi không có file hoặc load lỗi — khi đó dùng hình khối.
    @MainActor
    static func load(
        pose: ShootingPose,
        metrics: FigureMetrics,
        bundle: Bundle = .main
    ) -> Entity? {
        guard let url = bundle.url(
            forResource: resourceName(for: pose.id),
            withExtension: "usdz"
        ) else {
            return nil
        }

        if let cachedPrototype = prototypeCache[url] {
            let cloned = cachedPrototype.clone(recursive: true)
            return wrapScaled(cloned, to: metrics.headHeight)
        }

        do {
            // `Entity.load` đồng bộ, có từ iOS 13 — chạy được cả hai nhánh iOS.
            //
            // - Important: KHÔNG dùng `ModelEntity(contentsOf:loadAsync:)`. Biến thể
            //   đó chỉ có từ **iOS 18**, nên dùng nó là hỏng nhánh iOS 17 — cùng
            //   kiểu lỗi đã xảy ra với `RealityView` trước đó.
            let prototype = try Entity.load(contentsOf: url)
            prototypeCache[url] = prototype
            let cloned = prototype.clone(recursive: true)

            return wrapScaled(cloned, to: metrics.headHeight)
        } catch {
            return nil
        }
    }

    /// Chiều cao người tham chiếu để suy ra chiều cao đầu.
    ///
    /// - Important: hằng số này chỉ dùng để quy đổi **chiều cao đầu**, không dùng
    ///   để so với chiều cao model. Model nướng ở hệ Y-up với đáy ở Y = 0, nên
    ///   `visualBounds.extents.y` là chiều cao thật của tư thế — ngồi thấp hơn đứng,
    ///   đúng như người thật. Ép mọi tư thế về cùng một chiều cao sẽ làm dáng ngồi
    ///   bị kéo giãn.
    nonisolated static let referenceHeight: CGFloat = 1.70

    /// Chiều cao đầu trong file đã nướng, tính bằng mét.
    ///
    /// - Important: đây là **hằng số đo trước**, không tính lúc chạy. RealityKit không
    ///   công bố đỉnh của `MeshResource` nên không đo được chiều cao đầu từ entity đã
    ///   nạp; đo trong app là bất khả thi.
    ///
    /// - Important: giá trị **đồng nhất cho cả sáu tư thế**, và đó là cả ý nghĩa của
    ///   việc chuẩn hoá — đầu người không nhỏ đi khi ngồi. Đo bằng cách cắt ngang
    ///   mesh và tìm chỗ thắt cổ, rồi lấy khoảng cách từ đỉnh:
    ///
    ///   ```
    ///   standing-straight  cao=1.798  cổ=0.270  vai=0.418
    ///   standing-hip       cao=1.790  cổ=0.277  vai=0.493
    ///   standing-aside     cao=1.738  cổ=0.235  vai=0.500
    ///   seated-straight    cao=1.331  cổ=0.273  vai=0.399
    ///   seated-lean        cao=1.366  cổ=0.260  vai=0.382
    ///   seated-chin        cao=1.752  cổ=0.254  vai=0.519
    ///   ```
    ///
    ///   Biên độ 0,235–0,277 là do đứng/ngồi nghiêng đầu, không phải người khác kích
    ///   cỡ; lấy trung bình 0,263.
    ///
    /// - Important: KHÔNG suy ra từ `referenceHeight / 7,5` (ra 0,227). Con số đó
    ///   gần đúng, nhưng **đường tính thì sai**: `chiều cao model / 7,5` cho ra kết quả
    ///   khác nhau giữa các tư thế — 0,177 với ngồi so với 0,240 với đứng, chênh 26% —
    ///   và đó chính là thứ đã làm người ngồi bị phóng to 1,28 lần, thân phình to và
    ///   chân chiếm gần hết khung. Chi tiết trong `wrapScaled`.
    nonisolated static let bakedHeadHeight: Float = 0.263

    /// Chiều cao nguyên bản của model **đứng** trong file, tính bằng mét.
    ///
    /// - Important: đây là mốc để quy đổi "chiều cao đầu mong muốn" thành "chiều cao
    ///   người mong muốn", rồi suy ra hệ số scale. Dùng chiều cao của **tư thế đứng**
    ///   vì đó là tư thế duy nhất so sánh được với chiều cao người thật; tư thế ngồi
    ///   vốn thấp hơn và không được dùng làm mốc.
    ///
    ///   Đo trên `pose-standing-straight.usdz` sau khi nướng.
    nonisolated static let referenceModelHeight: Float = 1.798

    /// Chiều cao model thật — đo trên **mesh con**, không đo trên entity gốc.
    ///
    /// - Important: hai chỗ đã làm hỏng mọi phép đo trước đây:
    ///
    ///   1. `visualBounds` trên entity gốc đo **cả cây prim** — ra `cao=1.70 rong=1.18
    ///      sau=2.88` trong khi riêng mesh chỉ `1.33 × 0.54 × 0.79`. Phần dư do
    ///      transform của prim cha, không phải thân người.
    ///   2. `relativeTo: entity` đo trong hệ của chính entity nên **loại bỏ
    ///      `entity.scale`** khỏi kết quả. Đo được: `RAW cao = 1.331169`,
    ///      `factor = 1.277073`, `SCALED cao = 1.331169` — không đổi dù nhân lên phải
    ///      ra `1.700000`. Nghĩa là `normalizeScale` **chưa bao giờ có tác dụng**.
    ///
    /// - Important: chỉ gọi `visualBounds` trên entity **mang `ModelComponent`** — đó là
    ///   mesh thật, nên prim `Xform` trung gian tự động bị bỏ qua. Và `relativeTo: nil`
    ///   để phép scale có hiệu lực.
    @MainActor
    static func measureFigureHeight(_ entity: Entity) -> Float? {
        var meshes = 0
        var lowest = Float.greatestFiniteMagnitude
        var highest = -Float.greatestFiniteMagnitude

        func visit(_ node: Entity) {
            if node.components[ModelComponent.self] != nil {
                meshes += 1
                // `relativeTo: nil` → hệ thế giới → **bao gồm** `entity.scale`.
                let box = node.visualBounds(relativeTo: nil)
                lowest = min(lowest, box.min.y)
                highest = max(highest, box.max.y)
            }
            for child in node.children { visit(child) }
        }

        visit(entity)
        guard meshes > 0, highest > lowest else { return nil }
        return highest - lowest
    }

    /// Điểm thấp nhất của cây entity, tính bằng mét.
    @MainActor
    static func lowestY(_ entity: Entity) -> Float? {
        var lowest = Float.greatestFiniteMagnitude
        var found = false

        func visit(_ node: Entity) {
            if node.components[ModelComponent.self] != nil {
                lowest = min(lowest, node.visualBounds(relativeTo: nil).min.y)
                found = true
            }
            for child in node.children { visit(child) }
        }

        visit(entity)
        return found ? lowest : nil
    }

    /// Bọc người trong một `Entity` cha rồi đặt tỉ lệ — hàm trả về chính wrapper đó.
    ///
    /// - Important: **bắt buộc phải bọc**. Gán `entity.scale` trực tiếp lên entity
    ///   gốc nạp từ USDZ **không có tác dụng** với phép đo, và RealityKit vẽ sai.
    ///   Đo thử cả ba cách trên thiết bị (model cao 1,700 m, đặt scale 1,5):
    ///
    ///   ```
    ///   A  gán entity.scale trực tiếp : 1.700 → 1.178   (tỉ lệ 0,69 — sai)
    ///   B  bọc bằng Entity cha       : 1.700 → 1.767   (≈ ×1,5 — đúng)
    ///   C  gán vào từng mesh con      : 1.700 → 1.178   (tỉ lệ 0,69 — sai)
    ///   ```
    ///
    ///   Nên toàn bộ cảnh phải dùng wrapper này làm nút gốc. `load` trả wrapper, không
    ///   trả entity nạp từ file.
    @MainActor
    static func wrapScaled(_ entity: Entity, to headHeight: CGFloat) -> Entity {
        let wrapper = Entity()
        guard let modelHeight = measureFigureHeight(entity), modelHeight > 0.0001,
              headHeight > 0 else {
            wrapper.addChild(entity)
            return wrapper
        }

        // - Important: dùng MỘT hệ số chung cho mọi tư thế, lấy từ tư thế **đứng**.
        //
        //   Trước đây chiều cao đầu được suy ra bằng `modelHeight / 7,5`, rồi scale
        //   theo chiều cao đầu đó. Sai ở chỗ: quy tắc "7,5 đầu bằng chiều cao" chỉ
        //   đúng với người **đứng**. Người ngồi cao 1,33 m bị ước thành đầu 0,177
        //   (thật 0,263), nên bị phóng to **1,28 lần**: thân phình to, chân chiếm gần
        //   hết khung, đầu bị đẩy lên sát mép trên. Đúng như ảnh trên iPhone thật.
        //
        //   Nếu scale từng tư thế theo đầu riêng thì lại lệch sang lỗi khác: người
        //   đứng ra 1,55 m trong khi người mẫu cao 1,70 m — họ phải cúi xuống mới
        //   khớp, tức app lại hỏng đúng việc nó sinh ra để làm.
        //
        //   Nên: một hệ số duy nhất đặt tư thế đứng khớp chiều cao người mẫu; các
        //   tư thế khác giữ nguyên tỉ lệ, nhờ đó ngồi tự động thấp hơn đúng như
        //   người thật. Đo ra:
        //
        //   ```
        //   hệ số = 1,70 / 1,798 = 0,9455
        //
        //   standing-straight  1,798 → 1,700  ← bằng chiều cao người
        //   standing-hip       1,790 → 1,692
        //   standing-aside     1,738 → 1,643
        //   seated-straight    1,331 → 1,258  ← thấp hơn hẳn
        //   seated-chin        1,752 → 1,657  ← tư thế này ngồi thẳng lưng
        //   seated-lean        1,366 → 1,292
        //   ```
        //
        //   Tham số vào là chiều cao đầu **mong muốn** của người mẫu, còn file có
        //   chiều cao đầu `bakedHeadHeight`. Muốn người đứng trong file cao đúng bằng
        //   người mẫu thì phải quy đổi qua **chiều cao đầu**, không qua chiều cao:
        //
        //   ```
        //   chiều cao người = chiều cao đầu × 7,5
        //   ```
        //
        //   Nhờ vậy đổi chiều cao người mẫu thì cả sáu tư thế co giãn đồng loạt, và
        //   người đứng luôn khớp chiều cao thật — đó là điều kiện để người mẫu không
        //   phải cúi xuống.
        let modelHead = bakedHeadHeight
        guard modelHead > 0.0001 else {
            wrapper.addChild(entity)
            return wrapper
        }
        let wantedHeight = Float(headHeight) * Float(FigureBuild.totalHeads)
        let standingModelHeight = referenceModelHeight
        guard standingModelHeight > 0.0001 else {
            wrapper.addChild(entity)
            return wrapper
        }
        let uniformScale = wantedHeight / standingModelHeight

        wrapper.addChild(entity)
        wrapper.scale = SIMD3(repeating: uniformScale)

        // Đặt đáy người xuống mặt đất (Y = 0).
        //
        // - Important: cần **điểm thấp nhất**, không phải chiều cao. File xuất từ Blender
        //   có thể không nằm gốc 0, mà đứng lơ lửng trên một đoạn nào đó.
        let lowestPoint = lowestY(wrapper) ?? 0
        wrapper.position.y -= lowestPoint
        return wrapper
    }
}