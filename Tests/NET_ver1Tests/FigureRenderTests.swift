import CoreGraphics
import RealityKit
import SwiftUI
import UIKit
import XCTest
@testable import NET_ver1

/// Dựng cảnh 3D thật của app, chụp lại, rồi kiểm **ảnh đã render**.
///
/// ## Vì sao cần
///
/// Những lỗi đã xảy ra với người 3D đều không bị test nào bắt: model nạp được, số
/// đo đúng, build sạch, test khác xanh — nhưng trên màn hình thì **không có gì cả**.
/// Nguyên nhân gốc là không ai từng nhìn app chạy.
///
/// Test này dựng đúng cảnh của app, chụp `ARView.snapshot()` rồi kiểm pixel ảnh.
/// Đếm trên ảnh đã render khác đếm trên file asset: nó nói về **cái đang hiện**,
/// nên bắt được đúng nhóm lỗi im lặng đó.
///
/// - Important: dùng **chính** `GuideSceneBuilder`, `SceneLighting`, `GuideCamera` và
///   `ShootingPose.verticalFieldOfView`. Dựng bản sao riêng thì test xanh trong khi
///   app vẫn hỏng — đúng kiểu lỗi đã xảy ra.
@MainActor
final class FigureRenderTests: XCTestCase {

    /// Kích thước ảnh chụp — đủ lớn để bóng người chiếm nhiều pixel.
    private static let renderSize = CGSize(width: 480, height: 640)

    /// Bóng người phải **hiện** trong khung, ở cả sáu tư thế.
    ///
    /// - Important: đây là phép kiểm bắt được lỗi thật. Trước khi có test này,
    ///   `standing-aside` **không hiện gì** — người nằm ở Z = −4,13 … −3,35 trong file
    ///   USDZ trong khi camera đứng ở Z dương, tức camera nằm sau lưng người; và
    ///   `seated-straight` chỉ hiện **bàn** chứ không thấy người.
    ///
    ///   Không có phép đo nào trên file bắt được: chiều cao, bề rộng, số mesh, tỉ lệ
    ///   cổ-vai đều đúng. Chỉ nhìn ảnh render mới thấy.
    func testGuideFigureIsActuallyVisible() async throws {
        for pose in ShootingPose.all {
            let image = try await renderImage(pose: pose, isAligned: false)
            guard let cgImage = image.cgImage else {
                return XCTFail("snapshot() không trả về CGImage cho `\(pose.id)`")
            }
            let pixels = Self.pixels(of: cgImage)
            let warm = pixels.filter { Self.isWarm($0) }.count

            XCTAssertGreaterThan(
                warm, 500,
                """
                `\(pose.id)`: ảnh chụp không thấy bóng người (pixel ấm=\(warm)). \
                Hinh dang (dau # la bong nguoi):\n\(Self.silhouette(of: cgImage)) \
                ||| mau pho bien: \(Self.histogram(pixels))
                """
            )
        }
    }

    /// Bóng người phải **báo trạng thái bằng màu**: cam khi đang hướng dẫn, xanh lá khi
    /// đã khớp.
    ///
    /// - Important: đây là thứ người mẫu nhìn để biết app đã chấp đạt chưa. Nếu vật
    ///   liệu bị bỏ qua âm thầm thì cảnh vẫn hiện, nhưng không bao giờ báo "đã đúng
    ///   chỗ" — và app mất đúng cái việc nó tồn tại để làm.
    func testFigureColourFollowsAlignment() async throws {
        let guiding = Self.pixels(of: try await render(pose: .seatedStraight, aligned: false))
        let aligned = Self.pixels(of: try await render(pose: .seatedStraight, aligned: true))

        let warmBefore = guiding.filter { Self.isWarm($0) }.count
        let greenBefore = guiding.filter { Self.isGreen($0) }.count
        let warmAfter = aligned.filter { Self.isWarm($0) }.count
        let greenAfter = aligned.filter { Self.isGreen($0) }.count

        XCTAssertGreaterThan(
            warmBefore, greenBefore,
            "Khi chưa khớp, bóng phải thiên về cam — ấm=\(warmBefore) xanh=\(greenBefore)"
        )
        // - Important: so sánh **cùng một loại pixel trước và sau**, không so chéo.
        //   Đo được: ấm 910.190 → 9.000, xanh 3.000 → 900.181. Bóng người chiếm
        //   khoảng 33% ảnh, nên cả hai nhóm đều lớn — nhưng chúng **thay chỗ cho
        //   nhau**. So chéo (đếm xanh sau > đếm ấm trước) là phép so vô nghĩa và đã
        //   làm test đỏ nhầm một lần.
        XCTAssertLessThan(
            warmAfter, warmBefore / 2,
            "Khi đã khớp, bóng phải bỏ màu cam — ấm còn \(warmAfter) so với \(warmBefore)"
        )
        XCTAssertGreaterThan(
            greenAfter, greenBefore + 500,
            "Khi đã khớp, bóng phải chuyển sang xanh lá — xanh tăng \(greenBefore) → \(greenAfter)"
        )
    }

    /// Ảnh chụp phải **không trống**: toàn một màu nền thì cảnh không dựng được.
    ///
    /// Cần riêng khỏi test màu, vì bóng người mờ có thể lẫn vào nền tối tới mức
    /// đếm màu không bắt được, trong khi ảnh vẫn chứng minh có nội dung.
    func testRenderIsNotBlank() async throws {
        let pixels = Self.pixels(of: try await render(pose: .standingStraight, aligned: false))
        let distinct = Set(pixels.map { "\($0)" }).count
        XCTAssertGreaterThan(
            distinct, 50,
            "Ảnh chụp gần như chỉ có một màu — cảnh nhiều khả năng không dựng được"
        )
    }

    /// Bóng người phải nằm **trọn trong khung**, không bị cắt ở cả bốn cạnh.
    ///
    /// - Important: trước đây có lần dùng khoảng cách sai khiến người chiếm 118% chiều
    ///   cao khung và bị cắt mất cả đầu lẫn chân. Không test nào phát hiện, vì test cũ
    ///   chỉ đo chiều cao của mesh chứ không đo **vị trí trong khung**.
    func testFigureFitsInsideFrame() async throws {
        let image = try await renderImage(pose: .standingStraight, isAligned: false)
        guard let cgImage = image.cgImage else {
            return XCTFail("snapshot() không trả về CGImage")
        }
        guard let rows = Self.rows(containingFigure: cgImage) else {
            return XCTFail("Không tìm thấy bóng người để kiểm vị trí")
        }

        XCTAssertGreaterThan(rows.lowerBound, 0, "Bóng người bị cắt ở đỉnh khung")
        XCTAssertLessThan(rows.upperBound, cgImage.height, "Bóng người bị cắt ở đáy khung")
    }

    /// Bóng người phải **chiếm gần hết** chiều cao khung.
    ///
    /// - Important: đây là phép kiểm bắt được lỗi căn khung. Cao độ camera từng lấy
    ///   theo đường mắt 1/3, lệch với `cameraDistance` vốn đã chọn để người chiếm 85%
    ///   khung. Hệ quả đo được trên app thật: khung nhìn chỉ từ Y = 0,361 trở lên, nên
    ///   **nửa dưới người nằm ngoài khung** — ảnh chụp chỉ thấy đầu và thân, mất chân.
    ///   Mọi phép đo khác đều đúng, kể cả `testFeetStartAtGroundLevel`, vì lỗi nằm ở
    ///   camera chứ không phải ở model.
    ///
    ///   Ngưỡng 45% rộng có chủ ý: bóng người chỉ chiếm 85% chiều cao khung, phần còn
    ///   lại là dự phòng trên đầu và dưới chân cho người mẫu dịch chuyển.
    func testFigureFillsMostOfTheFrame() async throws {
        let image = try await renderImage(pose: .standingStraight, isAligned: false)
        guard let cgImage = image.cgImage,
              let rows = Self.rows(containingFigure: cgImage) else {
            return XCTFail("Không tìm thấy bóng người để đo độ chiếm khung")
        }

        let coverage = Double(rows.count) / Double(cgImage.height)
        XCTAssertGreaterThan(
            coverage, 0.45,
            "Bóng người chỉ chiếm \(Int(coverage * 100))% chiều cao khung — bị cắt cụt"
        )
        XCTAssertLessThan(
            coverage, 0.95,
            "Bóng người chiếm \(Int(coverage * 100))% khung — tràn ra ngoài"
        )
    }

    // MARK: - Dựng cảnh

    private enum SnapshotFailure: Error {
        case noImage
        case renderTimeout
    }

    private func render(pose: ShootingPose, aligned: Bool) async throws -> CGImage {
        let image = try await renderImage(pose: pose, isAligned: aligned)
        guard let cgImage = image.cgImage else { throw SnapshotFailure.noImage }
        return cgImage
    }

    /// Nhánh iOS 18+ phải cho ra **cùng khung hình** với nhánh `ARView`.
    ///
    /// - Important: đây là phép kiểm đáng lẽ phải có từ trước, vì trên iOS 18+ app
    ///   chạy nhánh `RealityView` chứ không phải `ARView` — tức **phần lớn máy thật hiện
    ///   nay không được test nào phủ**. Đã xảy ra hệ quả: nhánh đó tạo
    ///   `PerspectiveCamera` rồi thêm vào anchor, nhưng `RealityView` **bỏ qua** camera
    ///   đó (API chỉ có `.virtual` và `.spatialTracking`), nên ảnh thật cho thấy người
    ///   bị cắt cụt và lệch — trong khi mọi test vẫn xanh vì chỉ dựng `ARView`.
    ///
    ///   Không so hai ảnh cho bằng nhau tuyệt đối: khung hình của hai API có thể lệch
    ///   vài pixel. Cái cần chắc là **người vẫn đứng vừa khung**, tức đầu và chân cùng
    ///   nằm trong ảnh và bóng chiếm phần lớn chiều cao — đúng những gì kiểm ở trên.
    func testRealityViewBranchFramesTheFigure() async throws {
        let image = try await renderImageWithVirtualCamera(
            pose: .standingStraight,
            isAligned: false
        )
        guard let cgImage = image.cgImage else {
            return XCTFail("cameraTarget không dựng được khung hình")
        }
        guard let rows = Self.rows(containingFigure: cgImage) else {
            return XCTFail("Camera ảo không nhìn thấy người — nhánh RealityView hỏng")
        }

        XCTAssertGreaterThan(rows.lowerBound, 0, "Đầu người bị cắt ở đỉnh khung")
        XCTAssertLessThan(rows.upperBound, cgImage.height, "Chân người bị cắt ở đáy khung")

        let coverage = Double(rows.count) / Double(cgImage.height)
        XCTAssertGreaterThan(
            coverage, 0.45,
            "Người chỉ chiếm \(Int(coverage * 100))% chiều cao khung — camera ảo đứng sai chỗ"
        )
        XCTAssertLessThan(
            coverage, 0.95,
            "Người chiếm \(Int(coverage * 100))% khung — tràn ra ngoài"
        )
    }

    /// Dựng cảnh theo **đúng** cách nhánh `RealityView` làm: không tạo camera riêng,
    /// chỉ đặt `cameraTarget`.
    private func renderImageWithVirtualCamera(
        pose: ShootingPose,
        isAligned: Bool
    ) async throws -> UIImage {
        let metrics = pose.metrics(userHeight: 1.70)
        let view = ARView(
            frame: CGRect(origin: .zero, size: Self.renderSize),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.environment.background = .color(
            .init(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        )
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)

        let anchor = AnchorEntity(world: .zero)
        let scene = GuideSceneBuilder.build(pose: pose, metrics: metrics)
        FigureMaterial.apply(to: scene, isAligned: isAligned)
        anchor.addChild(scene)
        for light in SceneLighting.make() { anchor.addChild(light) }
        view.scene.addAnchor(anchor)

        // Camera ảo nhìn về entity rỗng ở tâm khung — tương đương `cameraTarget`.
        let target = GuideCamera.target(for: pose)
        anchor.addChild(target)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = Float(ShootingPose.verticalFieldOfView)
        camera.position = target.position + SIMD3<Float>(0, 0, Float(pose.cameraDistance))
        anchor.addChild(camera)

        for _ in 0..<25 {
            try await Task.sleep(nanoseconds: 80_000_000)
            if let image = await snapshot(of: view) { return image }
        }
        throw SnapshotFailure.renderTimeout
    }

    /// Chờ RealityKit kịp render rồi chụp.
    ///
    /// `snapshot` có thể trả `nil` ở những lần đầu khi chưa có khung hình nào — vì
    /// vậy phải thử lại chứ không kiểm một lần rồi kết luận cảnh hỏng.
    private func renderImage(pose: ShootingPose, isAligned: Bool) async throws -> UIImage {
        let metrics = pose.metrics(userHeight: 1.70)

        // - Important: `.nonAR` là bắt buộc. Dùng session thật thì máy ảo không có
        //   camera, `ARView` không dựng được khung nào và `snapshot()` luôn trả `nil`
        //   — tức test xanh trong khi cảnh vẫn hỏng.
        let view = ARView(
            frame: CGRect(origin: .zero, size: Self.renderSize),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.environment.background = .color(
            .init(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        )
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)

        let anchor = AnchorEntity(world: .zero)
        let scene = GuideSceneBuilder.build(pose: pose, metrics: metrics)
        FigureMaterial.apply(to: scene, isAligned: isAligned)
        anchor.addChild(scene)

        let camera = PerspectiveCamera()
        camera.name = GuideCamera.entityName
        camera.camera.fieldOfViewInDegrees = Float(ShootingPose.verticalFieldOfView)
        camera.position = GuideCamera.position(for: pose)
        anchor.addChild(camera)
        for light in SceneLighting.make() { anchor.addChild(light) }
        view.scene.addAnchor(anchor)

        for _ in 0..<25 {
            try await Task.sleep(nanoseconds: 80_000_000)
            if let image = await snapshot(of: view) { return image }
        }
        throw SnapshotFailure.renderTimeout
    }

    private func snapshot(of view: ARView) async -> UIImage? {
        await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Đọc pixel

    /// Mọi pixel của ảnh, chuẩn hoá về 0...1.
    ///
    /// - Important: đọc thẳng `dataProvider` thay vì vẽ lại bằng CoreGraphics — cách
    ///   vẽ lại có thể đổi thứ tự kênh (BGRA ↔ RGBA) và cho ra màu bị đảo, lúc đó
    ///   phép đo màu sẽ "đúng" một cách sai.
    private static func pixels(of image: CGImage) -> [SIMD3<Float>] {
        guard let bytes = bytes(of: image) else { return [] }
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(image.width * image.height)
        for y in 0..<image.height {
            let row = y * image.bytesPerRow
            for x in 0..<image.width {
                let offset = row + x * 4
                guard offset + 3 < bytes.count else { continue }
                result.append(SIMD3(
                    Float(bytes[offset]) / 255,
                    Float(bytes[offset + 1]) / 255,
                    Float(bytes[offset + 2]) / 255
                ))
            }
        }
        return result
    }

    /// Pixel **ấm** — bóng người khi đang hướng dẫn, và mọi thứ màu nâu đỏ trong ảnh.
    ///
    /// - Important: không so sánh bằng màu gốc của `FigureMaterial`. Vật liệu pha trộn
    ///   với nền ở alpha 0,30 rồi nhân với ánh sáng, nên màu đo được lệch khá xa màu
    ///   gốc: đo được `0,58 / 0,27 / 0,17` so với màu gốc `1,00 / 0,45 / 0,20`. So
    ///   sát màu gốc là phép đếm luôn ra 0 — tức báo "không có hình" trong khi hình
    ///   vẫn ở đó.
    ///
    ///   Nhận diện theo **quan hệ giữa các kênh** thì bền hơn nhiều: bóng cam luôn
    ///   đỏ rõ hơn xanh dương, và nền xanh-tối thì ngược lại.
    private static func isWarm(_ pixel: SIMD3<Float>) -> Bool {
        pixel.x > 0.20 && pixel.x - pixel.z > 0.12 && pixel.x > pixel.y + 0.10
    }

    /// Pixel **xanh lá** — bóng người khi đã khớp chỗ.
    private static func isGreen(_ pixel: SIMD3<Float>) -> Bool {
        pixel.y > 0.18 && pixel.y - pixel.x > 0.06 && pixel.y - pixel.z > 0.04
    }

    /// Các hàng có pixel ấm — dùng để kiểm bóng người có bị cắt không.
    private static func rows(containingFigure image: CGImage) -> ClosedRange<Int>? {
        let pixels = self.pixels(of: image)
        let height = image.height
        let width = image.width
        guard !pixels.isEmpty else { return nil }

        var rows: [Int] = []
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                guard index < pixels.count else { break }
                if isWarm(pixels[index]) {
                    rows.append(row)
                    break
                }
            }
        }
        guard let low = rows.min(), let high = rows.max() else { return nil }
        return low...high
    }

    /// Vẽ khung hình đã render bằng chữ: `#` là pixel bóng người, còn lại là nền.
    ///
    /// - Important: đây là bước **nhìn**, không phải đo. Số đo phân biệt được "có hình"
    ///   với "không có hình", nhưng không phân biệt được "đầu ở trên" với "đầu ở dưới",
    ///   cũng không thấy được người bị cắt cụt. Đó là lý do các lỗi tư thế trước đây
    ///   lọt qua mọi phép đo.
    private static func silhouette(of image: CGImage, rows: Int = 24, columns: Int = 18) -> String {
        guard let bytes = bytes(of: image) else { return "khong doc duoc anh" }

        var lines: [String] = []
        let cellHeight = max(image.height / rows, 1)
        let cellWidth = max(image.width / columns, 1)

        for row in 0..<rows {
            var line = ""
            for column in 0..<columns {
                var figure = 0
                var total = 0
                for y in (row * cellHeight)..<min((row + 1) * cellHeight, image.height) {
                    for x in (column * cellWidth)..<min((column + 1) * cellWidth, image.width) {
                        let offset = y * image.bytesPerRow + x * 4
                        guard offset + 3 < bytes.count else { continue }
                        total += 1
                        let pixel = SIMD3(
                            Float(bytes[offset]) / 255,
                            Float(bytes[offset + 1]) / 255,
                            Float(bytes[offset + 2]) / 255
                        )
                        if isWarm(pixel) { figure += 1 }
                    }
                }
                let ratio = total > 0 ? Double(figure) / Double(total) : 0
                line += ratio > 0.5 ? "#" : (ratio > 0.15 ? "+" : ".")
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Mười màu phổ biến nhất trong ảnh — dùng để nhìn ra vấn đề khi phép đếm trượt.
    private static func histogram(_ pixels: [SIMD3<Float>]) -> String {
        var buckets: [String: Int] = [:]
        for pixel in pixels {
            let key = String(format: "%.2f/%.2f/%.2f", pixel.x, pixel.y, pixel.z)
            buckets[key, default: 0] += 1
        }
        return buckets.sorted { $0.value > $1.value }.prefix(8)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func bytes(of image: CGImage) -> [UInt8]? {
        guard let data = image.dataProvider?.data else { return nil }
        return [UInt8](Data(referencing: data as CFData))
    }
}