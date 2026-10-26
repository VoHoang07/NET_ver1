import RealityKit
import UIKit
import XCTest
@testable import NET_ver1

/// Dò xem `ARView` trong test host có render được không.
///
/// Tách riêng vì `snapshot()` trong test host đã làm treo cả phiên test — và nguyên
/// nhân phải biết trước khi thêm bất kỳ phép kiểm nào dựa vào ảnh chụp.
@MainActor
final class RenderProbeTests: XCTestCase {

    func testSnapshotReturns() async throws {
        let view = ARView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.environment.background = .color(.init(white: 0.2, alpha: 1))

        let anchor = AnchorEntity(world: .zero)
        let box = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.4, 0.4, 0.4)),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        anchor.addChild(box)

        let camera = PerspectiveCamera()
        camera.position = SIMD3(0, 0, 2)
        anchor.addChild(camera)
        view.scene.addAnchor(anchor)

        // Chờ một nhịp để RealityKit kịp dựng khung hình đầu.
        try await Task.sleep(nanoseconds: 500_000_000)

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }

        XCTAssertNotNil(image, "snapshot() tra nil — ARView khong render duoc trong test host")
        print("PROBE size=\(image?.size ?? .zero)")
    }
}