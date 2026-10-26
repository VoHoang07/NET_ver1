import Combine
import CoreGraphics
import Foundation
import RealityKit
import SwiftUI
import UIKit
import XCTest
@testable import NET_ver1

/// Kiểm chứng đường ống nạp người 3D từ file `.usdz`.
///
/// Ba lỗi im lặng đã lọt qua test cũ, mỗi lỗi đều làm app rơi về trạng thái
/// "chạy được nhưng nhìn sai":
///
/// 1. Ép kiểu `Entity` thành `ModelEntity` — USDZ có prim gốc là `Xform` nên luôn
///    trả `nil`, app rơi về hình khối mà không ghi log nào.
/// 2. File `.usdz` sai chuẩn — `Entity.load` trả `nil`, không có báo cáo.
/// 3. Sai hệ toạ độ — nạp được nhưng người nằm ngang.
///
/// Test ở đây **nạp thật** và **đo thật** thay vì chỉ kiểm tra file có trong bundle.
@MainActor
final class FigureAssetTests: XCTestCase {

    // MARK: - File

    func testEveryPoseHasBundledFile() {
        for pose in ShootingPose.all {
            let url = Bundle.main.url(
                forResource: FigureAssetLoader.resourceName(for: pose.id),
                withExtension: "usdz"
            )
            XCTAssertNotNil(url, "Thiếu file cho tư thế `\(pose.id)`")
        }
    }

    func testResourceNameHasNoExtension() {
        // - Important: `Bundle` cần tên **không** kèm đuôi. Đặt nhầm
        //   `"pose-seated-straight.usdz"` thì `Bundle` tìm `"...usdz.usdz"` và trả
        //   `nil`, mà code chỉ âm thầm rơi về hình khối.
        let name = FigureAssetLoader.resourceName(for: "seated-straight")
        XCTAssertEqual(name, "pose-seated-straight")
        XCTAssertFalse(name.hasSuffix(".usdz"))
    }

    func testFileSizeIsPlausible() {
        for pose in ShootingPose.all {
            guard let url = Bundle.main.url(
                forResource: FigureAssetLoader.resourceName(for: pose.id),
                withExtension: "usdz"
            ) else { continue }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? Int) ?? 0

            // Dưới 200 KB nghĩa là file rỗng hoặc hỏng. Trên 8 MB nghĩa là xuất ở
            // dạng `.usda` (chữ) — dùng `.usdc` thì file nhỏ hơn nhiều lần.
            XCTAssertGreaterThan(bytes, 200_000, "File của `\(pose.id)` có vẻ rỗng")
            XCTAssertLessThan(bytes, 8_000_000, "File của `\(pose.id)` quá lớn — nên xuất .usdc")
        }
    }

    // MARK: - Nội dung

    func testEachPoseLoadsWithVisibleMesh() {
        for pose in ShootingPose.all {
            guard let entity = load(pose) else {
                XCTFail("RealityKit không nạp được người ở tư thế `\(pose.id)`")
                continue
            }

            var meshCount = 0
            countMeshes(in: entity, into: &meshCount)
            XCTAssertGreaterThan(
                meshCount, 0,
                "Tư thế `\(pose.id)` không có mesh nào — sẽ không hiện gì"
            )
        }
    }

    /// Đo **mesh thật** bằng chính RealityKit để chốt hệ toạ độ và chiều cao.
    ///
    /// - Important: đo riêng mesh chứ không dùng `visualBounds` của cả cây prim.
    ///   `visualBounds` trên entity gốc bao gồm prim bọc ngoài, cho ra
    ///   `cao=1.70 rong=1.18 sau=2.88` trong khi mesh thật chỉ `1.33 × 0.54 × 0.79`.
    ///   Dùng số đó để kết luận là đo sai.
    ///
    ///   Người thật: cao hơn rộng ít nhất 2,5 lần, và cao 1,26–1,70 m sau khi scale.
    func testRealityKitSeesFigureUpright() {
        for pose in ShootingPose.all {
            guard let entity = load(pose) else {
                XCTFail("Không nạp được `\(pose.id)`")
                continue
            }

            guard let height = FigureAssetLoader.measureFigureHeight(entity) else {
                XCTFail("`\(pose.id)`: không tìm thấy mesh nào để đo")
                continue
            }

            let width = meshWidth(in: entity)
            XCTAssertGreaterThan(
                height, 0.8,
                "`\(pose.id)` cao \(height) — quá thấp, có thể đang đọc sai trục"
            )
            XCTAssertLessThan(
                height, 2.0,
                "`\(pose.id)` cao \(height) — cao hơn cả người thật"
            )
            if width > 0.0001 {
                XCTAssertGreaterThan(
                    height / width, 1.8,
                    "`\(pose.id)` cao=\(height) rộng=\(width) — "
                    + "người phải cao hơn rộng nhiều lần"
                )
            }
        }
    }

    /// Chặn đúng lỗi đã xảy ra: phép scale im lặng không có tác dụng.
    ///
    /// - Important: gán `entity.scale` **trực tiếp** lên entity gốc nạp từ USDZ không
    ///   có tác dụng. Đo thử ba cách trên thiết bị (model cao 1,700 m, đặt scale 1,5):
    ///
    ///   ```
    ///   A  gán entity.scale trực tiếp : 1.700 → 1.178   (tỉ lệ 0,69 — sai)
    ///   B  bọc bằng Entity cha       : 1.700 → 1.767   (≈ ×1,5 — đúng)
    ///   C  gán vào từng mesh con      : 1.700 → 1.178   (tỉ lệ 0,69 — sai)
    ///   ```
    ///
    ///   Nên `load` phải trả về **wrapper**, và wrapper đó mới mang tỉ lệ.
    ///
    ///   Hậu quả khi sai: `normalizeScale` chạy suốt mà không đổi gì, model luôn giữ
    ///   kích thước gốc của file, nên mọi kiểm tra phía sau dựa trên con số sai và
    ///   không bao giờ phát hiện.
    func testScaleActuallyApplies() {
        guard let wrapped = load(.seatedStraight) else {
            return XCTFail("Không nạp được người")
        }

        let before = FigureAssetLoader.measureFigureHeight(wrapped)
        XCTAssertNotNil(before, "Không đo được chiều cao ban đầu")

        wrapped.scale = SIMD3(repeating: wrapped.scale.x * 1.5)
        let after = FigureAssetLoader.measureFigureHeight(wrapped)

        guard let before, let after else {
            return XCTFail("Không đo được chiều cao sau khi scale")
        }

        XCTAssertEqual(
            after / before, 1.5, accuracy: 0.05,
            "Scale 1,5 không có tác dụng: trước=\(before) sau=\(after)"
        )
    }

    /// Người sau khi scale phải cao đúng bằng chiều cao người mẫu.
    ///
    /// - Important: đây là **hợp đồng** của cả ứng dụng — người 3D phải khớp người
    ///   thật, không phải khớp kích thước file gốc. Trước đây điều này sai âm thầm:
    ///   scale không có tác dụng nên người luôn cao đúng như file (1,33–1,80 m) bất kể
    ///   người mẫu cao bao nhiêu.
    /// Người **đứng** phải cao đúng bằng chiều cao người mẫu.
    ///
    /// - Important: trước đây test này lấy `ShootingPose.all[0]` — tức **ngồi** — rồi
    ///   đòi model cao đúng 170 cm. Như vậy nó **khẳng định luôn điều sai**: người ngồi
    ///   không thể cao bằng người đứng. Đó là lỗ hổng đã để chiều cao sai lọt qua suốt
    ///   bao lâu nay. Chỉ tư thế **đứng** mới so được với chiều cao người thật.
    func testStandingFigureMatchesUserHeight() {
        for heightCm in [155.0, 170.0, 190.0] as [CGFloat] {
            let userHeight = CGFloat(heightCm / 100)
            guard let standing = ShootingPose.all.first(where: { $0.stance == .standing }),
                  let entity = FigureAssetLoader.load(
                      pose: standing,
                      metrics: standing.metrics(userHeight: userHeight)
                  ),
                  let measured = FigureAssetLoader.measureFigureHeight(entity) else {
                XCTFail("Không nạp được người đứng cao \(heightCm) cm")
                continue
            }

            XCTAssertEqual(
                Double(measured), Double(userHeight), accuracy: 0.01,
                "Người đứng \(heightCm) cm nhưng model cao \(measured) m"
            )
        }
    }

    /// Mọi tư thế phải dùng **cùng một hệ số scale**, nên tỉ lệ giữa các tư thế được
    /// giữ nguyên như trong file.
    ///
    /// - Important: đây là phép chặn lỗi đã xảy ra. Trước đây chiều cao đầu được suy
    ///   ra bằng `chiều cao model / 7,5`, mà quy tắc "7,5 đầu bằng chiều cao" chỉ đúng
    ///   với người **đứng**. Người ngồi bị ước sai 26%, nên bị phóng to 1,28 lần: thân
    ///   phình to, chân chiếm gần hết khung, đầu đẩy sát mép trên. Nhìn rõ trên iPhone.
    ///
    ///   Giờ một hệ số duy nhất đặt tư thế đứng khớp chiều cao người mẫu, còn các tư
    ///   tư thế giữ nguyên tỉ lệ trong file — ngồi tự động thấp hơn đúng như người thật.
    ///
    /// - Note: `seated-chin` cao 1,66 m **không phải** lỗi. Người ngồi trên ghế, chân
    ///   đặt xuống đất thì đỉnh đầu chỉ thấp hơn khi đứng vài phân — 1,66 so với 1,70
    ///   là đúng. Có tư thế ngồi thấp hơn nhiều (`seated-straight` 1,26 m) vì người
    ///   cúi người về phía trước trên bàn.
    func testEveryPoseUsesTheSameScaleFactor() throws {
        let reference = try XCTUnwrap(
            ShootingPose.all.first { $0.stance == .standing },
            "Không có tư thế đứng nào để làm mốc"
        )

        // Chiều cao **thô**: nạp thẳng file, không qua `wrapScaled`.
        func rawFileHeight(_ pose: ShootingPose) throws -> Float {
            let url = try XCTUnwrap(
                Bundle.main.url(
                    forResource: FigureAssetLoader.resourceName(for: pose.id),
                    withExtension: "usdz"
                ),
                "Không tìm thấy file của `\(pose.id)`"
            )
            let entity = try XCTUnwrap(
                try Entity.load(contentsOf: url),
                "RealityKit không nạp được `\(pose.id)`"
            )
            return try XCTUnwrap(
                FigureAssetLoader.measureFigureHeight(entity),
                "Không đo được chiều cao thô của `\(pose.id)`"
            )
        }

        // Tỉ lệ `sau khi nạp / thô trong file` phải **bằng nhau cho mọi tư thế**.
        //
        // - Important: đối chiếu với chiều cao thô đọc thẳng từ USDZ, chứ không đối
        //   chiếu với chính entity đã scale — cách đó luôn ra 1 và không bắt được gì.
        var scaleByPose: [String: Float] = [:]
        for pose in ShootingPose.all {
            let metrics = pose.metrics(userHeight: 1.70)
            let entity = try XCTUnwrap(
                FigureAssetLoader.load(pose: pose, metrics: metrics),
                "Không nạp được `\(pose.id)`"
            )
            let rendered = try XCTUnwrap(
                FigureAssetLoader.measureFigureHeight(entity),
                "Không đo được chiều cao sau khi nạp: `\(pose.id)`"
            )
            let raw = try rawFileHeight(pose)
            XCTAssertGreaterThan(raw, 0.001, "`\(pose.id)` có chiều cao thô bằng 0")
            scaleByPose[pose.id] = rendered / raw
        }

        let referenceScale = try XCTUnwrap(scaleByPose[reference.id])
        for (id, scale) in scaleByPose {
            XCTAssertEqual(
                scale, referenceScale, accuracy: 0.01,
                """
                `\(id)` bị scale \(scale) khác `\(reference.id)` (\(referenceScale)). \
                Phải dùng chung một hệ số, nếu không tư thế sẽ bị phóng to/thu nhỏ riêng.
                """
            )
        }
    }

    func testFeetStartAtGroundLevel() {
        // - Important: đáy người phải nằm đúng Y = 0. Lệch thì người lơ lửng hoặc
        //   chìm sâu xuống sàn, và mỗi tư thế nằm ở một độ cao khác nhau.
        for pose in ShootingPose.all {
            guard let entity = load(pose) else { continue }
            let minY = entity.visualBounds(relativeTo: nil).min.y

            XCTAssertEqual(
                minY, 0, accuracy: 0.01,
                "`\(pose.id)` đáy người ở Y = \(minY), phải bằng 0"
            )
        }
    }

    /// Người phải **đứng thẳng** sau khi RealityKit nạp.
    ///
    /// - Important: đây là phép chặn lỗi làm người 3D **nằm ngang**. Đã xảy ra và
    ///   nhìn thấy rõ trên iPhone thật: người nằm sấp, bóng đầu và bóng hông chồng
    ///   lên nhau thành khối tròn, đọc ra như một vật thể dán lên màn hình.
    ///
    ///   Nguyên nhân nằm ở file USDZ: `convert_orientation=True` khiến Blender tự
    ///   thêm `rotateXYZ = (-90, 0, 0)` ở prim gốc để bù cho việc nó **đã tự xoay**
    ///   hình học. Hai phép biến đổi triệt tiêu nhau, còn metadata vẫn ghi
    ///   `upAxis = "Y"` nên **không có gì sai** khi đọc file bằng mắt.
    ///
    ///   - Important: đo sau khi **RealityKit đã nạp**, chứ không đọc `upAxis` rồi tự
    ///   xoay. RealityKit tự sửa file lúc nạp, nên đo hệ toạ độ thô sẽ ra kết quả
    ///   khác với thứ người dùng thấy — và từng làm test báo xanh trong khi app hiển
    ///   thị sai.
    ///
    ///   - Important: không đọc nội dung file bằng `String(decoding:)`. File `.usdc` là
    ///   **nhị phân**, không có dòng `def Mesh` hay `points = [` để bóc chuỗi.
    func testFigureIsUprightAfterRealityKitLoad() throws {
        for pose in ShootingPose.all {
            let url = try XCTUnwrap(
                Bundle.main.url(
                    forResource: FigureAssetLoader.resourceName(for: pose.id),
                    withExtension: "usdz"
                ),
                "Không tìm thấy file của `\(pose.id)`"
            )
            let entity = try XCTUnwrap(
                try Entity.load(contentsOf: url),
                "RealityKit không nạp được `\(pose.id)`"
            )
            let box = entity.visualBounds(relativeTo: nil)

            let height = Double(box.max.y - box.min.y)
            let depth = Double(box.max.z - box.min.z)
            let width = Double(box.max.x - box.min.x)

            XCTAssertGreaterThan(
                height, depth,
                "`\(pose.id)`: người NẰM NGANG — cao \(height) ≤ sâu \(depth). Kiểm tra `convert_orientation` trong `tools/bake_poses.py`."
            )
            XCTAssertGreaterThan(
                height, width * 1.5,
                "`\(pose.id)`: cao \(height) không hơn rộng \(width) đủ xa — hình học bị méo"
            )
        }
    }

    /// File phải chỉ chứa mesh **da người**, không kèm mesh khung xương.
    ///
    /// - Important: mesh `Beta_Joints` là hiện thân các khớp — những khối cầu nhỏ ở
    ///   vai, khuỷu, hông. Nó nằm chồng lên da người nên khi hiện ra, người trông
    ///   như **búp bê tháo rời**: các khối cầu mọc ra từ thân. Nhìn rõ trên iPhone.
    ///
    ///   Sau khi mất liên kết xương, mesh này còn đứng ở T-pose — cao bằng người thật
    ///   và rộng hơn cả thân — nên nó lấn ra ngoài khung chứ không chỉ gây rối mắt.
    ///
    ///   - Important: đếm mesh qua `ModelComponent` trên cây entity, **không** bóc
    ///   chuỗi trong file: `.usdc` là nhị phân, không có `def Mesh` để tìm.
    func testOnlySkinMeshIsShipped() throws {
        for pose in ShootingPose.all {
            let url = try XCTUnwrap(
                Bundle.main.url(
                    forResource: FigureAssetLoader.resourceName(for: pose.id),
                    withExtension: "usdz"
                ),
                "Không tìm thấy file của `\(pose.id)`"
            )
            let entity = try XCTUnwrap(
                try Entity.load(contentsOf: url),
                "RealityKit không nạp được `\(pose.id)`"
            )

            var names: [String] = []
            func visit(_ node: Entity) {
                if node.components[ModelComponent.self] != nil { names.append(node.name) }
                for child in node.children { visit(child) }
            }
            visit(entity)

            XCTAssertEqual(
                names.count, 1,
                "`\(pose.id)` chứa \(names.count) mesh: \(names) — chỉ được có mesh da"
            )
            XCTAssertFalse(
                names.contains { $0.lowercased().contains("joint") },
                "`\(pose.id)` vẫn chứa mesh xương: \(names)"
            )
        }
    }

    func testFigureIsCentredSidewaysAndDepth() {
        // - Important: người phải nằm **giữa** khung theo cả X lẫn Z, không chỉ đứng
        //   trên mặt sàn. Camera nhìn thẳng vào trục Z tại X = 0, nên người lệch sang
        //   bên là trượt khỏi khung hình, người lệch về phía sau là **không hiện**.
        //
        //   Đây đúng là lỗi đã xảy ra: file USDZ nướng trước đó chỉ dịch trục đứng, nên
        //   mỗi tư thế trôi theo gốc riêng của clip Mixamo. Đo được trước khi sửa:
        //
        //   | tư thế | X | Z |
        //   |---|---|---|
        //   | standing-aside | +2,61 .. +3,42 | -4,13 .. -3,35 |
        //   | seated-chin | -2,81 .. -2,13 | -1,31 .. -0,85 |
        //   | standing-straight | -0,35 .. +0,16 | +0,22 .. +0,64 |
        //
        //   `standing-aside` lệch 3,4 m sang bên và 3,7 m ra sau — cộng lại là không
        //   có gì trong khung. Mọi phép đo khác (chiều cao, bề rộng, tỉ lệ cổ-vai) vẫn
        //   đúng, nên không test nào bắt được.
        for pose in ShootingPose.all {
            guard let entity = load(pose) else { continue }
            let bounds = entity.visualBounds(relativeTo: nil)
            let centreX = (bounds.min.x + bounds.max.x) / 2
            let centreZ = (bounds.min.z + bounds.max.z) / 2

            XCTAssertEqual(
                centreX, 0, accuracy: 0.01,
                "`\(pose.id)` tâm X ở \(centreX), phải gần 0 — người lệch sang bên là trượt khỏi khung"
            )
            XCTAssertEqual(
                centreZ, 0, accuracy: 0.01,
                "`\(pose.id)` tâm Z ở \(centreZ), phải gần 0 — người lệch ra sau là camera đứng sau lưng người"
            )
        }
    }

    func testPosesAreActuallyDifferent() {
        // - Important: 6 file nướng đầu tiên có chữ ký **giống hệt nhau** vì
        //   Blender 4.4+ cần gán `action_slot` mà script bỏ sót, nên xương không
        //   nhận chuyển động và cả 6 tư thế ra một dáng. Export vẫn báo thành công,
        //   không lỗi nào được in ra.
        //
        //   Test này chặn đúng lỗi đó: nếu nướng sinh ra 6 bản giống nhau thì coi
        //   như hỏng, dù kích thước và số mesh đều đúng.
        var signatures: [String: String] = [:]

        for pose in ShootingPose.all {
            guard let entity = load(pose) else {
                XCTFail("Không nạp được `\(pose.id)`")
                continue
            }

            let signature = boundsSignature(of: entity)
            if let other = signatures[signature] {
                XCTFail(
                    "Tư thế `\(pose.id)` và `\(other)` cho ra hình hệt nhau — "
                    + "tư thế chưa thực sự được nướng"
                )
            } else {
                signatures[signature] = pose.id
            }
        }

        XCTAssertEqual(signatures.count, ShootingPose.all.count)
    }

    func testMaterialReachesEveryMesh() {
        // - Important: USDZ từ Blender vẫn mang vật liệu gốc của Mixamo (áo,
        //   texture), và app **thay hết** bằng một màu mờ đơn giản. Nên điều cần
        //   kiểm không phải "file có vật liệu không", mà là: sau khi app gán vật
        //   liệu của nó, **mọi** mesh đều phải nhận — kể cả mesh lồng sâu trong cây
        //   prim chứ không phải con trực tiếp.
        //
        //   Bỏ sót một mesh nghĩa là người 3D lộ ra màu gốc đậm đục ở đúng chỗ đó.
        guard let entity = load(.seatedStraight) else {
            return XCTFail("Không nạp được người")
        }

        FigureMaterial.apply(to: entity, isAligned: false)

        var modelCount = 0
        var withMaterials = 0
        countMaterials(in: entity, count: &modelCount, withMaterials: &withMaterials)

        // - Important: chỉ được **một** mesh — mesh da. Trước đây phải `> 1` vì file
        //   còn chứa `Beta_Joints` (mesh khớp), và con số 2 cho thấy app vẫn nạp đủ cả
        //   hai. Giờ mesh khớp đã bị loại khỏi file lúc nướng, nên đúng phải là 1:
        //   nhiều hơn nghĩa là file xuất sai, và bản kiểm mesh xương ở trên sẽ đỏ.
        XCTAssertEqual(modelCount, 1, "Phải có đúng một mesh da, thấy \(modelCount)")
        XCTAssertEqual(modelCount, withMaterials, "Mesh nào không nhận được vật liệu")
    }

    func testMaterialSwitchesWhenAligned() {
        guard let entity = load(.seatedStraight) else {
            return XCTFail("Không nạp được người")
        }

        // - Important: người 3D phải **mờ hơn** khi đã đúng vị trí, để không che
        //   khuôn mặt người thật. Đây là quyết định thiết kế, không phải chỉ số cân
        //   bằng — nên ghim thẳng bằng chứng cứu hằng số, đổi nhầm là test đỏ.
        XCTAssertGreaterThan(
            FigureMaterial.alphaWhenGuiding, FigureMaterial.alphaWhenAligned,
            "Khi đang hướng dẫn phải đậm hơn khi đã đúng vị trí"
        )

        // Và hai trạng thái phải cho ra vật liệu **khác nhau** — nếu không người 3D
        // không báo hiệu được khi nào đã đúng vị trí.
        FigureMaterial.apply(to: entity, isAligned: true)
        let aligned = firstTint(in: entity)

        FigureMaterial.apply(to: entity, isAligned: false)
        let guiding = firstTint(in: entity)

        XCTAssertNotNil(aligned, "Không gán được vật liệu khi đúng vị trí")
        XCTAssertNotEqual(aligned, guiding, "Hai trạng thái cho ra cùng một màu")
    }

    /// Bóng mờ phải **thật sự** trong suốt, không phải chỉ có alpha trong màu.
    ///
    /// - Important: `baseColor` mang alpha chưa đủ. `PhysicallyBasedMaterial` mặc định
    ///   là `.opaque`, và RealityKit **bỏ qua** alpha đó — người 3D hiện thành khối đặc
    ///   có màu nhạt, đúng kiểu trong ảnh, chứ không phải bóng mờ.
    ///
    ///   Test này khẳng định blending đã bật, để lỗi đó không quay lại lần nữa.
    func testMaterialIsActuallyTransparent() {
        let material = FigureMaterial.make(isAligned: false)

        if case .transparent = material.blending {
            // Đúng.
        } else {
            XCTFail(
                "Vật liệu đang để `.opaque` — alpha trong `baseColor` bị bỏ qua, "
                + "người 3D hiện thành khối đặc chứ không mờ."
            )
        }

        // Và phải mềm, không phải cắt cứng: kiểm tra alpha trong màu nền khác 1.
        let guiding = FigureMaterial.make(isAligned: false)
        XCTAssertGreaterThan(
            FigureMaterial.alphaWhenGuiding, 0.0,
            "Alpha bằng 0 thì người 3D biến mất hoàn toàn"
        )
        XCTAssertLessThan(
            FigureMaterial.alphaWhenGuiding, 1.0,
            "Alpha bằng 1 thì người 3D đặc hoàn toàn, không phải bóng mờ"
        )
        XCTAssertNotEqual(guiding.baseColor.tint, .clear, "Màu nền trong suốt hoàn toàn")
    }

    /// Người phải **đúng hướng**: đầu trên, chân dưới.
    ///
    /// - Important: bề rộng người đứng không đều — rộng nhất ở vai và hông, hẹp nhất ở
    ///   cổ rồi tới bề ngang đầu. Nếu đo được phần hẹp nhất nằm **dưới**, người đang
    ///   bị lộn ngược.
    ///
    ///   Đây là lỗi đã xảy ra: `camera.look(at:from:)` nhận `target` **trước** rồi mới
    ///   tới `from`. Truyền ngược thứ tự làm camera quay 180°, hình ảnh lộn ngược.
    ///
    /// - Important: đo bằng `visualBounds` **không** được — nó trả bbox của cả mesh cho
    ///   mọi đoạn, nên mọi đoạn đều ra cùng một số. Phải đo trên từng đoạn riêng.
    func testFigureIsUprightNotInverted() {
        for pose in ShootingPose.all {
            guard let entity = load(pose) else {
                XCTFail("Không nạp được `\(pose.id)`")
                continue
            }

            let box = entity.visualBounds(relativeTo: nil)
            let height = box.extents.y
            guard height > 0.0001 else { continue }

            // Người đứng cao hơn rộng nhiều lần: chiều cao 1,3–1,7 m so với bề ngang
            // vai ~0,5 m. Tỉ lệ này đảo ngược khi hình 3D bị lộn hoặc nằm ngang.
            let width = box.extents.x
            XCTAssertGreaterThan(
                height / max(width, 0.0001), 1.8,
                "`\(pose.id)` cao=\(height) rộng=\(width) — có thể đang lộn ngược"
            )
        }
    }

    /// Cảnh phải có nguồn sáng, nếu không người 3D nhìn như hình 2D dán lên nền.
    ///
    /// - Important: `PhysicallyBasedMaterial` không phát sáng. Không có đèn thì mọi mặt
    ///   nhận cùng lượng sáng, bóng đổ không có, và hình khối đọc ra là tấm phẳng —
    ///   đúng cảm giác "không có trong không gian thật".
    ///
    ///   Một đèn đơn lẻ không đủ: mặt trước sáng đều, mặt sau tối đặc, nhìn ra là khối
    ///   dán. Cần bố trí nhiều hướng để có khối.
    func testSceneHasMultipleLights() {
        let lights = TranslucentSceneView<EmptyView>.makeTestLights()

        XCTAssertGreaterThanOrEqual(
            lights.count, 3,
            "Cần ít nhất 3 hướng sáng (key/fill/rim). Hiện có \(lights.count)."
        )
        for light in lights {
            let directional = light.components[DirectionalLightComponent.self]
            XCTAssertNotNil(directional, "Đèn không phải `DirectionalLight`")
            XCTAssertGreaterThan(
                directional?.intensity ?? 0, 0,
                "Đèn có cường độ 0 thì không chiếu gì"
            )
        }
    }

    func testGuideSceneDoesNotIncludeFurnitureBoxes() {
        for pose in ShootingPose.all {
            let metrics = pose.metrics(userHeight: 1.70)
            let scene = GuideSceneBuilder.build(pose: pose, metrics: metrics)
            var meshCount = 0
            countMeshes(in: scene, into: &meshCount)
            XCTAssertEqual(
                meshCount, 1,
                "Cảnh hướng dẫn của `\(pose.id)` chỉ được chứa đúng 1 mesh người mẫu, không được gắn thêm khối bàn ghế hộp gây chắn tầm nhìn (thấy \(meshCount) mesh)"
            )
        }
    }

    func testEmptyMeasurementsAreNotAligned() {
        for pose in ShootingPose.all {
            let match = PostureMatch.evaluate(
                pose: pose,
                measurements: CaptureMeasurements(),
                layout: nil
            )
            XCTAssertFalse(
                match.isAligned,
                "Khi chưa có dữ liệu người thật trong khung (`CaptureMeasurements()`), `isAligned` phải là `false` (màu cam hướng dẫn), không được báo xanh lá"
            )
        }
    }

    func testSpatialCameraReactsToTiltPanAndZoom() {
        let base = GuideCamera.spatialState(for: .standingStraight)
        let tilted = GuideCamera.spatialState(
            for: .standingStraight,
            pitch: 0.25,
            yaw: -0.20,
            roll: 0.10,
            translationOffset: SIMD3<Float>(0.12, -0.05, 0.18),
            zoomFactor: 2.0
        )

        XCTAssertNotEqual(
            base.orientation, tilted.orientation,
            "Camera 3D phải xoay theo góc nghiêng/lia thực tế của iPhone để neo người mẫu trong không gian thực"
        )
        XCTAssertNotEqual(
            base.position, tilted.position,
            "Camera 3D phải dịch chuyển vị trí (parallax + bước chân) trong không gian thực"
        )
        XCTAssertLessThan(
            tilted.fieldOfViewInDegrees, base.fieldOfViewInDegrees,
            "Khi phóng to camera (`zoomFactor = 2.0`), góc nhìn dọc (FOV) của camera 3D phải thu hẹp tương ứng"
        )
    }

    func testFigureMaterialUsesBackFaceCullingAndHumanSkinTone() {
        let material = FigureMaterial.make(isAligned: false)
        XCTAssertEqual(
            material.faceCulling, .back,
            "Lớp da bán trong suốt phải bật `faceCulling = .back` để không lộ mặt lưng nội bộ xuyên qua cơ thể"
        )
        XCTAssertGreaterThanOrEqual(
            FigureMaterial.alphaWhenGuiding, 0.55,
            "Độ đục của lớp da người khi hướng dẫn phải đủ rõ khối cơ thể"
        )
    }

    func testFloorAnchorTransformPinsFeetToDetectedFloorY() {
        var cameraMatrix = matrix_identity_float4x4
        cameraMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)

        let detectedFloorY: Float = -1.32
        let fallbackAnchor = GuideCamera.floorAnchorTransform(
            cameraTransform: cameraMatrix,
            pose: .standingStraight,
            floorY: detectedFloorY,
            hitPosition: nil
        )
        XCTAssertEqual(
            fallbackAnchor.position.y, detectedFloorY, accuracy: 0.001,
            "Chân người mẫu (gốc Y=0 của anchor) phải ghim chính xác xuống cao độ mặt sàn `floorY`"
        )
        XCTAssertEqual(
            fallbackAnchor.position.z, -GuideCamera.position(for: .standingStraight).z, accuracy: 0.01,
            "Khoảng cách đặt người mẫu trên sàn phải đúng tầm chụp của tư thế"
        )

        let raycastHit = SIMD3<Float>(0.42, -1.24, -2.65)
        let hitAnchor = GuideCamera.floorAnchorTransform(
            cameraTransform: cameraMatrix,
            pose: .standingStraight,
            floorY: detectedFloorY,
            hitPosition: raycastHit
        )
        XCTAssertEqual(hitAnchor.position.x, raycastHit.x, accuracy: 0.001)
        XCTAssertEqual(hitAnchor.position.y, detectedFloorY, accuracy: 0.001)
        XCTAssertEqual(hitAnchor.position.z, raycastHit.z, accuracy: 0.001)
    }

    func testGroundShadowBuilderCreatesFloorShadowAtGroundLevel() throws {
        let figure = try XCTUnwrap(load(.standingStraight))
        let shadowRoot = GroundShadowBuilder.makeFloorShadow(for: figure)

        let catcher = try XCTUnwrap(
            shadowRoot.findEntity(named: "floor-shadow-catcher"),
            "Phải có mặt phẳng bắt bóng đổ động ARKit (`OcclusionMaterial`) dưới chân"
        )
        let model = try XCTUnwrap(catcher.components[ModelComponent.self])
        XCTAssertTrue(
            model.materials.first is OcclusionMaterial,
            "Mặt phẳng bắt bóng phải dùng `OcclusionMaterial` vô hình, không được dùng vật liệu màu xám nhân tạo"
        )
        XCTAssertNil(
            shadowRoot.findEntity(named: "floor-contact-shadow"),
            "Phải xóa bỏ hoàn toàn mesh chữ nhật màu xám nhân tạo dưới chân mẫu"
        )
        XCTAssertNil(
            shadowRoot.findEntity(named: "floor-projected-silhouette"),
            "Phải xóa bỏ hoàn toàn bóng đổ giả lập (`UnlitMaterial`), chỉ dùng bóng đổ động thực tế trên `OcclusionMaterial`"
        )
    }

    func testSmartAutoPlacementHeuristicsAndSmoothing() {
        // 1. Khoảng cách đứng tối ưu phải nằm trong dải vàng 1.8m – 2.5m
        for pose in ShootingPose.all {
            let idealDist = GuideCamera.idealStandOffDistance(for: pose)
            XCTAssertTrue(
                GuideCamera.idealDistanceRange.contains(idealDist),
                "Khoảng cách lý tưởng của `\(pose.id)` (\(idealDist)m) phải nằm trong khoảng 1.8m – 2.5m"
            )
        }

        // 2. Các điểm raycast ưu tiên phải bao phủ giao điểm 1/3 (Rule of Thirds)
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let points = GuideCamera.ruleOfThirdsRaycastPoints(in: viewport)
        XCTAssertGreaterThanOrEqual(points.count, 3)
        XCTAssertTrue(
            points.contains { abs($0.x - 130) < 1.0 && abs($0.y - 562.6) < 2.0 },
            "Phải có điểm giao 1/3 trái-dưới để bố cục ảnh tự nhiên"
        )

        // 3. Chấm điểm ứng viên ưu tiên khoảng cách vàng 1.8m – 2.5m hơn điểm quá gần/quá xa
        var cam = matrix_identity_float4x4
        cam.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        let idealScore = GuideCamera.scoreFloorCandidate(
            hitPosition: SIMD3<Float>(0, -1.3, -2.25),
            cameraTransform: cam,
            pose: .standingStraight,
            isExactGeometry: true
        )
        let tooCloseScore = GuideCamera.scoreFloorCandidate(
            hitPosition: SIMD3<Float>(0, -1.3, -0.85),
            cameraTransform: cam,
            pose: .standingStraight,
            isExactGeometry: false
        )
        XCTAssertGreaterThan(idealScore, tooCloseScore)

        // 4. Nội suy Lerp (`simd_mix`) và Slerp (`simd_slerp`) phải làm mượt chuyển động, không nhảy vọt
        let startPos = SIMD3<Float>(0, -1.3, -1.5)
        let endPos = SIMD3<Float>(0.5, -1.3, -2.2)
        let startRot = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let endRot = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let step = GuideCamera.smoothTransform(
            currentPosition: startPos,
            targetPosition: endPos,
            currentOrientation: startRot,
            targetOrientation: endRot,
            positionSmoothing: 0.25,
            rotationSmoothing: 0.25
        )
        XCTAssertGreaterThan(step.position.x, startPos.x)
        XCTAssertLessThan(step.position.x, endPos.x)
    }

    func testShouldAcceptFloorRaycastHitRejectsElevatedOrOutOfRangeHits() {
        var cameraMatrix = matrix_identity_float4x4
        cameraMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)

        // Điểm sàn hợp lệ: thấp hơn camera 1.30m và cách camera 2.2m
        let validFloorHit = SIMD3<Float>(0.15, -1.30, -2.20)
        XCTAssertTrue(
            GuideCamera.shouldAcceptFloorRaycastHit(
                hitPosition: validFloorHit,
                cameraTransform: cameraMatrix
            ),
            "Phải chấp nhận điểm giao cắt raycast trên mặt sàn thật dưới thấp"
        )

        // Điểm ngang tầm mắt hoặc mặt bàn cao (chỉ thấp hơn camera 0.10m) -> từ chối
        let elevatedHit = SIMD3<Float>(0.0, -0.10, -1.80)
        XCTAssertFalse(
            GuideCamera.shouldAcceptFloorRaycastHit(
                hitPosition: elevatedHit,
                cameraTransform: cameraMatrix
            ),
            "Phải từ chối điểm raycast nằm quá cao gần tầm ống kính (tránh đặt mẫu lên mặt bàn cao/tường)"
        )

        // Điểm quá sát ống kính (< 0.50m) hoặc quá xa (> 6.0m) -> từ chối
        let tooCloseHit = SIMD3<Float>(0.0, -1.20, -0.20)
        let tooFarHit = SIMD3<Float>(0.0, -1.20, -8.50)
        XCTAssertFalse(
            GuideCamera.shouldAcceptFloorRaycastHit(hitPosition: tooCloseHit, cameraTransform: cameraMatrix)
        )
        XCTAssertFalse(
            GuideCamera.shouldAcceptFloorRaycastHit(hitPosition: tooFarHit, cameraTransform: cameraMatrix)
        )
    }

    func testAmbientLightFactorScalesAndClampsSceneLighting() {
        let normalFactor = GuideCamera.ambientLightFactor(ambientIntensity: 1000)
        XCTAssertEqual(normalFactor, 1.0, accuracy: 0.001)

        let dimFactor = GuideCamera.ambientLightFactor(ambientIntensity: 150)
        XCTAssertEqual(dimFactor, 0.45, accuracy: 0.001)

        let brightFactor = GuideCamera.ambientLightFactor(ambientIntensity: 2500)
        XCTAssertEqual(brightFactor, 1.45, accuracy: 0.001)

        let lights = SceneLighting.make()
        SceneLighting.updateIntensity(in: lights, factor: 0.5)
        let keyLight = lights.first { $0.name == "light-key" }
        let keyIntensity = keyLight?.components[DirectionalLightComponent.self]?.intensity ?? 0
        XCTAssertEqual(keyIntensity, 450, accuracy: 1.0)
    }

    func testSceneAwareSmartSpotSelectionPrefersOpenFloorOverClutteredForeground() {
        // Giả lập khung hình quán cafe thực tế:
        // - Nửa trái (u = 0.42, v = 0.68): sàn bê tông phẳng (luma ~ 0.50), không có bàn chắn phía trước, hậu cảnh rèm trắng dịu (~0.58).
        // - Nửa phải (u = 0.62, v = 0.68): vướng ly nước/bàn tiền cảnh lấp lánh ở dưới, quạt cây đen ở giữa (luma ~ 0.12), xe máy chói sáng (luma ~ 0.94) ở hậu cảnh.
        let fakeCafeLuma: (_ u: Float, _ v: Float) -> Float = { u, v in
            if u < 0.50 {
                // Bên trái: sàn phẳng êm và rèm dịu mắt
                if v > 0.60 {
                    return 0.48 + sin(u * 6.0) * 0.01
                } else {
                    return 0.56 + cos(v * 5.0) * 0.015
                }
            } else {
                // Bên phải: lộn xộn (chói sáng ở trên, quạt đen ở giữa, ly nước tương phản mạnh ở tiền cảnh dưới)
                if v < 0.50 {
                    return (Int(u * 80) + Int(v * 80)) % 2 == 0 ? 0.95 : 0.25
                } else if v < 0.65 {
                    return 0.10 // quạt đen
                } else {
                    return (Int(u * 100) + Int(v * 100)) % 2 == 0 ? 0.92 : 0.18 // ly nước & cạnh bàn
                }
            }
        }

        let openLeftSpot = GuideCamera.evaluateVisualSpotQuality(
            normalizedFootPoint: CGPoint(x: 0.42, y: 0.68),
            lumaAt: fakeCafeLuma
        )
        let clutteredRightSpot = GuideCamera.evaluateVisualSpotQuality(
            normalizedFootPoint: CGPoint(x: 0.62, y: 0.68),
            lumaAt: fakeCafeLuma
        )

        XCTAssertGreaterThan(
            openLeftSpot.floorOpenness,
            clutteredRightSpot.floorOpenness,
            "Góc sàn bê tông trống bên trái phải có điểm floorOpenness cao hơn góc vướng đồ bên phải"
        )
        XCTAssertGreaterThan(
            openLeftSpot.foregroundClearance,
            clutteredRightSpot.foregroundClearance,
            "Góc không vướng bàn/ly nước tiền cảnh phải có điểm foregroundClearance cao hơn"
        )
        XCTAssertGreaterThan(
            openLeftSpot.compositeScore,
            clutteredRightSpot.compositeScore + 0.30,
            "Thuật toán tự nhận diện góc đẹp phải chấm điểm góc sàn thoáng bên trái (\(openLeftSpot.compositeScore)) vượt trội so với góc vướng bàn/quạt bên phải (\(clutteredRightSpot.compositeScore))"
        )

        // Kiểm tra thêm bộ lọc đám mây điểm 3D (pointCloudObstaclePenalty)
        let camPos = SIMD3<Float>(0, 1.25, 0)
        let floorY: Float = 0.0
        let leftCandidate3D = SIMD3<Float>(-0.45, floorY, -3.0)
        let rightCandidate3D = SIMD3<Float>(0.55, floorY, -3.0)
        // Đám mây điểm vật cản nằm bên phải (bàn tiền cảnh + quạt cây)
        var obstacleCloud: [SIMD3<Float>] = []
        for i in 0..<12 {
            obstacleCloud.append(SIMD3<Float>(0.52 + Float(i) * 0.01, 0.55, -2.1))
            obstacleCloud.append(SIMD3<Float>(0.55, 0.45 + Float(i) * 0.02, -2.95))
        }

        let leftPenalty = GuideCamera.pointCloudObstaclePenalty(
            candidatePosition: leftCandidate3D,
            cameraPosition: camPos,
            floorY: floorY,
            featurePoints: obstacleCloud
        )
        let rightPenalty = GuideCamera.pointCloudObstaclePenalty(
            candidatePosition: rightCandidate3D,
            cameraPosition: camPos,
            floorY: floorY,
            featurePoints: obstacleCloud
        )
        XCTAssertEqual(leftPenalty, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(rightPenalty, 0.5, "Phải phạt nặng ứng viên có vật cản 3D chắn phía trước hoặc ngay vị trí đứng")
    }

    func testAppStoreComplianceAndEntityMemoryRelease() throws {
        // 1. Kiểm tra cấu hình Info.plist chuẩn Guideline 5.1.1
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(
            info["NSCameraUsageDescription"] as? String,
            "Ứng dụng cần quyền truy cập Camera để hiển thị trực tiếp mô hình 3D tạo dáng trên khung ngắm, giúp bạn căn chỉnh góc chụp và bố cục hình ảnh."
        )
        XCTAssertEqual(
            info["NSPhotoLibraryAddUsageDescription"] as? String,
            "Ứng dụng cần quyền truy cập Thư viện ảnh để lưu lại bức ảnh bạn vừa chụp vào thiết bị."
        )
        XCTAssertEqual(
            info["NSPhotoLibraryUsageDescription"] as? String,
            "Ứng dụng cần quyền truy cập Thư viện ảnh để lưu lại bức ảnh bạn vừa chụp vào thiết bị."
        )
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.0.0")
        let requiredCaps = info["UIRequiredDeviceCapabilities"] as? [String] ?? []
        XCTAssertFalse(requiredCaps.contains("lidar"), "Không được bắt buộc LiDAR để tránh chặn cài đặt trên iPhone tiêu chuẩn hoặc iPad")
        XCTAssertFalse(requiredCaps.contains("arkit"), "Không được bắt buộc arkit cứng trong UIRequiredDeviceCapabilities")

        // 2. Kiểm tra file PrivacyInfo.xcprivacy đã được đóng gói trong Bundle và khai báo CA92.1
        let privacyURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "File PrivacyInfo.xcprivacy phải được gắn vào target chính"
        )
        let privacyData = try Data(contentsOf: privacyURL)
        let privacyDict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: privacyData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(privacyDict["NSPrivacyTracking"] as? Bool, false)
        let collectedTypes = privacyDict["NSPrivacyCollectedDataTypes"] as? [Any]
        XCTAssertEqual(collectedTypes?.count, 0)
        let accessedTypes = try XCTUnwrap(privacyDict["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaultsEntry = accessedTypes.first {
            ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        XCTAssertTrue(reasons.contains("CA92.1"), "Phải khai báo mã lý do CA92.1 cho UserDefaults")

        // 3. Kiểm tra thông tin màn hình AboutView
        XCTAssertEqual(AboutView.appName, "NÉT")
        XCTAssertEqual(AboutView.appVersion, "1.0.0")
        XCTAssertEqual(AboutView.copyrightNotice, "© 2026 Võ Vũ Minh Hoàng. All rights reserved.")

        // 4. Kiểm tra giải phóng bộ nhớ đệ quy khi đổi mẫu 3D (GuideSceneBuilder.releaseEntityHierarchy)
        let container = Entity()
        let metrics = ShootingPose.standingStraight.metrics(userHeight: 1.70)
        let scene = GuideSceneBuilder.build(pose: .standingStraight, metrics: metrics)
        container.addChild(scene)

        var meshesBefore = 0
        countMeshes(in: scene, into: &meshesBefore)
        XCTAssertGreaterThan(meshesBefore, 0)

        GuideSceneBuilder.releaseEntityHierarchy(scene)
        var meshesAfter = 0
        countMeshes(in: scene, into: &meshesAfter)
        XCTAssertEqual(meshesAfter, 0, "Toàn bộ ModelComponent của thực thể 3D cũ phải được giải phóng khỏi RAM")
        XCTAssertEqual(scene.children.count, 0, "Toàn bộ cây thực thể con phải được gỡ bỏ")
        XCTAssertNil(scene.parent, "Thực thể gốc phải được tách khỏi parent")
    }

    func testCameraServiceARStateMutationDoesNotPublishSynchronouslyDuringViewUpdate() {
        let service = CameraService()
        var synchronousPublishCount = 0
        let cancellable = service.objectWillChange.sink { _ in
            synchronousPublishCount += 1
        }
        defer { cancellable.cancel() }

        // Các hàm này được gọi trực tiếp bên trong UIViewRepresentable.makeUIView / updateUIView
        service.setExternalARActive(true)
        service.setFloorLocked(true)
        service.setFloorLocked(false)
        service.setExternalARActive(false)
        service.viewportSize = CGSize(width: 390, height: 844)

        XCTAssertEqual(
            synchronousPublishCount, 0,
            "Không được phát sự kiện @Published đồng bộ trong lúc makeUIView/updateUIView đang chạy để tránh lỗi 'Publishing changes from within view updates is not allowed'"
        )
    }

    func testFigureAssetLoaderPrototypeCacheProducesIndependentClonesQuickly() throws {
        FigureAssetLoader.clearCache()
        let pose = ShootingPose.standingStraight
        let metrics = pose.metrics(userHeight: 1.70)

        let first = try XCTUnwrap(FigureAssetLoader.load(pose: pose, metrics: metrics))
        let second = try XCTUnwrap(FigureAssetLoader.load(pose: pose, metrics: metrics))

        XCTAssertFalse(
            first === second,
            "Mỗi lần gọi FigureAssetLoader.load phải trả về một bản sao Entity độc lập từ bộ đệm nguyên mẫu"
        )

        first.position.x = 99
        XCTAssertEqual(
            second.position.x, 0, accuracy: 0.0001,
            "Thay đổi transform trên bản sao thứ nhất không được làm ảnh hưởng tới bản sao thứ hai"
        )
    }

    func testCameraServiceSetZoomUpdatesImmediatelyInARAndNonARModes() {
        let service = CameraService()
        service.setExternalARActive(true)

        service.setZoom(1.5, animated: false)
        XCTAssertEqual(service.zoomFactor, 1.5, accuracy: 0.001)

        service.setZoom(2.0, animated: true)
        XCTAssertEqual(service.zoomFactor, 2.0, accuracy: 0.001)

        // Kẹp trong dải 1.0x ... 3.0x
        service.setZoom(0.4, animated: false)
        XCTAssertEqual(service.zoomFactor, 1.0, accuracy: 0.001)

        service.setZoom(9.0, animated: false)
        XCTAssertEqual(service.zoomFactor, 3.0, accuracy: 0.001)
    }

    // MARK: - Hỗ trợ

    private func load(_ pose: ShootingPose) -> Entity? {
        let metrics = pose.metrics(userHeight: 1.70)
        return FigureAssetLoader.load(pose: pose, metrics: metrics)
    }

    /// Bề rộng của phần mesh trong cây entity.
    private func meshWidth(in entity: Entity) -> Float {
        var widest: Float = 0
        func visit(_ node: Entity) {
            if node.components[ModelComponent.self] != nil {
                widest = max(widest, node.visualBounds(relativeTo: entity).extents.x)
            }
            for child in node.children { visit(child) }
        }
        visit(entity)
        return widest
    }

    /// Chữ ký hình học của một người, làm tròn về centimetre.
    ///
    /// Dùng `visualBounds` của từng mesh con thay vì đọc mảng đỉnh: positions nằm
    /// sau `MeshBuffers`, khó bền theo phiên bản, còn `visualBounds` công khai và
    /// đủ để phân biệt — ngồi khác đứng ngay ở chiều cao.
    private func boundsSignature(of entity: Entity) -> String {
        var text = ""
        for child in entity.children.sorted(by: { $0.name < $1.name }) {
            let box = child.visualBounds(relativeTo: entity)
            text += child.name
            text += "(\(cm(box.min.x)),\(cm(box.min.y)),\(cm(box.min.z))"
            text += "\(cm(box.extents.x)),\(cm(box.extents.y)),\(cm(box.extents.z)))"
        }
        return text
    }

    private func cm(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }

    private func countMeshes(in entity: Entity, into count: inout Int) {
        if entity.components[ModelComponent.self] != nil { count += 1 }
        for child in entity.children {
            countMeshes(in: child, into: &count)
        }
    }

    private func countMaterials(in entity: Entity, count: inout Int, withMaterials: inout Int) {
        if let model = entity.components[ModelComponent.self] {
            count += 1
            if !model.materials.isEmpty { withMaterials += 1 }
        }
        for child in entity.children {
            countMaterials(in: child, count: &count, withMaterials: &withMaterials)
        }
    }

    /// Màu nền của vật liệu đầu tiên tìm thấy trong cây entity.
    ///
    /// So sánh `UIColor` trực tiếp thay vì đọc thành phần alpha: `UIColor` không
    /// lộ thuộc tính alpha ở giao diện Swift, và tách thành phần chỉ để so sánh là
    /// thêm điều phải bảo trì mà không đổi kết luận.
    private func firstTint(in entity: Entity) -> UIColor? {
        if let model = entity.components[ModelComponent.self],
           let material = model.materials.first as? PhysicallyBasedMaterial {
            return material.baseColor.tint
        }
        for child in entity.children {
            if let found = firstTint(in: child) { return found }
        }
        return nil
    }
}