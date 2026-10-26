#if !targetEnvironment(simulator)
import ARKit
#endif
import AVFoundation
import Combine
import CoreGraphics
import CoreMotion
import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Thuật toán Bố Cục Nhiếp Ảnh Thông Minh (Smart Auto-Placement & Photographic Heuristics)
/// và điều khiển Camera / Điểm neo AR thực tế.
enum GuideCamera {
    static let entityName = "guide-camera"

    /// Khoảng cách chụp chân dung lý tưởng (mét) để lấy trọn dáng từ đầu tới chân,
    /// đỉnh đầu nằm ở đường 1/3 trên và bàn chân nằm ở vùng 1/5 dưới khung hình.
    static let idealDistanceRange: ClosedRange<Float> = 1.80...2.50

    /// Thiết bị thật có hỗ trợ ARKit World Tracking (`ARWorldTrackingConfiguration`) để
    /// dò mặt sàn thật và ghim mẫu 3D xuống đất hay không.
    static var supportsRealSpaceAR: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }

    /// Trạng thái biến đổi 3D của camera trong không gian thực.
    struct SpatialState: Equatable {
        var position: SIMD3<Float>
        var orientation: simd_quatf
        var fieldOfViewInDegrees: Float
    }

    /// Cao độ tâm khung nhìn theo tư thế, tính bằng mét.
    /// Hạ nhẹ tâm camera (~10cm so với trung điểm cơ thể) để đẩy hình chiếu người mẫu
    /// nhích lên vùng khung ngắm trống (15%..75% chiều cao màn hình), không chạm thanh nút dưới đáy.
    @MainActor
    private static func centerHeight(for pose: ShootingPose) -> Float {
        switch pose.stance {
        case .seated:
            return 0.52
        case .standing:
            return 0.72
        }
    }

    /// Vị trí camera gốc cho tư thế đã chọn, tính bằng mét.
    @MainActor
    static func position(for pose: ShootingPose) -> SIMD3<Float> {
        let distance = pose.cameraDistance
        let frameCenterY = centerHeight(for: pose)
        return SIMD3<Float>(0, frameCenterY, Float(distance))
    }

    /// Tâm khung nhìn mục tiêu cho tư thế đã chọn, tính bằng mét.
    @MainActor
    static func target(for pose: ShootingPose) -> Entity {
        let target = Entity()
        target.name = "guide-camera-target"
        target.position = SIMD3<Float>(0, centerHeight(for: pose), 0)
        return target
    }

    // MARK: - Smart Auto-Placement Heuristics (Khoảng cách 1.8m-2.5m + Rule of Thirds + Look-At + Lerp/Slerp)

    /// Khoảng cách đứng tối ưu từ ống kính tới mẫu 3D (nằm trong dải vàng 1.8m – 2.5m).
    ///
    /// - Dáng ngồi (`.seated`): `2.15m` để lấy trọn người ngồi và khoảng trống thoáng trên đầu.
    /// - Dáng đứng (`.standing`): `2.42m` để lấy trọn toàn thân từ đầu tới gót chân mà không chạm thanh điều khiển.
    @MainActor
    static func idealStandOffDistance(for pose: ShootingPose) -> Float {
        switch pose.stance {
        case .seated:
            return 2.15
        case .standing:
            return 2.42
        }
    }

    /// Lưới 15 điểm ứng viên chuẩn hoá `(u, v)` nằm trên **Dải Sàn Mở (Golden Open-Floor Band)**:
    /// - Trục ngang `u` quét từ đường 1/3 trái (`0.36`), lệch trái nhẹ (`0.43`), tâm (`0.50`), lệch phải nhẹ (`0.57`) tới đường 1/3 phải (`0.64`).
    /// - Trục dọc `v` nằm quanh đường 1/3 dưới (`0.65`, `0.69`, `0.72`) — nơi mặt sàn thật lộ rõ nhất trong quán cafe/phòng,
    ///   luôn cao hơn mép bàn tiền cảnh (`v > 0.75`) và thanh chọn tư thế (`v = 0.80`).
    static let compositionCandidateNormalizedPoints: [CGPoint] = {
        let columns: [CGFloat] = [0.42, 0.50, 0.58, 1.0 / 3.0, 2.0 / 3.0]
        let rows: [CGFloat] = [2.0 / 3.0, 0.69, 0.72]
        var points: [CGPoint] = []
        for row in rows {
            for col in columns {
                points.append(CGPoint(x: col, y: row))
            }
        }
        return points
    }()

    /// Tập hợp các điểm bắn tia Raycast ưu tiên theo **Bố cục 1/3 & Dải Sàn Mở** trên khung ngắm.
    @MainActor
    static func ruleOfThirdsRaycastPoints(in bounds: CGRect) -> [CGPoint] {
        let w = bounds.width > 0 ? bounds.width : 390
        let h = bounds.height > 0 ? bounds.height : 844
        return compositionCandidateNormalizedPoints.map { pt in
            CGPoint(x: pt.x * w, y: pt.y * h)
        }
    }

    /// Chỉ số đánh giá thị giác của một vị trí đứng ứng viên `(u, v_foot)` trực tiếp từ ảnh camera:
    /// - `floorOpenness`: độ phẳng/trống trải của mặt sàn ngay dưới chân (sàn bê tông/gạch trống có gradient thấp).
    /// - `foregroundClearance`: mức độ thông thoáng phía trước chân (`v_foot + 0.04 ... v_foot + 0.14`), phát hiện bàn/cốc nước chắn tiền cảnh.
    /// - `midBodyClearance`: mức độ thông thoáng vùng đầu gối – thắt lưng (`v_foot - 0.14 ... v_foot - 0.04`), tránh quạt cây/ghế đẩu.
    /// - `backgroundHarmony`: độ sạch và dịu sáng của hậu cảnh sau đầu/vai (`v_foot - 0.36 ... v_foot - 0.18`), ưu tiên rèm/tường phẳng, tránh chói sáng/xe cộ lộn xộn.
    struct VisualSpotMetrics: Equatable {
        let floorOpenness: Float
        let foregroundClearance: Float
        let midBodyClearance: Float
        let backgroundHarmony: Float
        let compositeScore: Float
    }

    /// Phân tích trực tiếp ma trận độ chói (Luma `0...1`) của khung hình tại điểm chân ứng viên `normalizedFootPoint` (`0...1`)
    /// để tìm ra **góc đứng thoáng và đẹp nhất trong khung hình**.
    static func evaluateVisualSpotQuality(
        normalizedFootPoint: CGPoint,
        lumaAt: (_ u: Float, _ v: Float) -> Float
    ) -> VisualSpotMetrics {
        let u = Float(min(max(normalizedFootPoint.x, 0.18), 0.82))
        let vFoot = Float(min(max(normalizedFootPoint.y, 0.52), 0.78))

        func analyzePatch(
            uCenter: Float,
            uHalfWidth: Float,
            vMin: Float,
            vMax: Float
        ) -> (meanLuma: Float, meanGrad: Float, stdDev: Float, glareRatio: Float) {
            let cols = 7
            let rows = 5
            var values = [Float]()
            values.reserveCapacity(cols * rows)
            var sum: Float = 0
            var glareCount: Int = 0
            var gradSum: Float = 0
            var gradCount: Int = 0

            for r in 0..<rows {
                let vt = Float(r) / Float(max(rows - 1, 1))
                let v = min(max(vMin + (vMax - vMin) * vt, 0.02), 0.98)
                for c in 0..<cols {
                    let ut = Float(c) / Float(max(cols - 1, 1)) * 2.0 - 1.0
                    let sampleU = min(max(uCenter + uHalfWidth * ut, 0.02), 0.98)
                    let luma = lumaAt(sampleU, v)
                    values.append(luma)
                    sum += luma
                    if luma > 0.84 {
                        glareCount += 1
                    }
                    if c > 0 {
                        let prevH = values[values.count - 2]
                        gradSum += abs(luma - prevH)
                        gradCount += 1
                    }
                    if r > 0 {
                        let prevV = values[values.count - 1 - cols]
                        gradSum += abs(luma - prevV)
                        gradCount += 1
                    }
                }
            }

            let count = Float(values.count)
            let mean = sum / max(count, 1)
            var varSum: Float = 0
            for val in values {
                let d = val - mean
                varSum += d * d
            }
            let std = sqrt(varSum / max(count, 1))
            let meanGrad = gradSum / Float(max(gradCount, 1))
            let glare = Float(glareCount) / max(count, 1)
            return (mean, meanGrad, std, glare)
        }

        // 1. Vùng sàn ngay dưới bàn chân: sàn trống có độ lệch chuẩn thấp và ít cạnh gắt
        let floorPatch = analyzePatch(
            uCenter: u,
            uHalfWidth: 0.055,
            vMin: vFoot - 0.035,
            vMax: vFoot + 0.035
        )
        let floorClutter = floorPatch.meanGrad * 3.8 + floorPatch.stdDev * 2.2 + floorPatch.glareRatio * 0.8
        let floorOpenness = min(max(1.0 - floorClutter, 0.0), 1.0)

        // 2. Hành lang tiền cảnh ngay bên dưới chân (phát hiện bàn cafe, ly nước, đĩa thức ăn chắn phía trước)
        let fgPatch = analyzePatch(
            uCenter: u,
            uHalfWidth: 0.065,
            vMin: vFoot + 0.035,
            vMax: min(vFoot + 0.145, 0.85)
        )
        // Nếu vùng tiền cảnh bên dưới có độ tương phản/lấp lánh cao hoặc lệch hẳn màu so với sàn -> đang vướng bàn/đồ vật tiền cảnh
        let floorToFgDiff = abs(fgPatch.meanLuma - floorPatch.meanLuma)
        let fgClutter = fgPatch.meanGrad * 4.0 + fgPatch.stdDev * 2.4 + floorToFgDiff * 1.4 + fgPatch.glareRatio * 0.9
        let foregroundClearance = min(max(1.0 - fgClutter, 0.0), 1.0)

        // 3. Vùng bắp chân – thắt lưng (phát hiện quạt cây màu đen, ghế đẩu, cạnh bàn thấp)
        let midPatch = analyzePatch(
            uCenter: u,
            uHalfWidth: 0.065,
            vMin: vFoot - 0.145,
            vMax: vFoot - 0.040
        )
        let darkObjectPenalty: Float = midPatch.meanLuma < 0.25 ? (0.25 - midPatch.meanLuma) * 2.5 : 0
        let midClutter = midPatch.meanGrad * 3.6 + midPatch.stdDev * 2.2 + darkObjectPenalty
        let midBodyClearance = min(max(1.0 - midClutter, 0.0), 1.0)

        // 4. Vùng hậu cảnh sau ngực và đầu (ưu tiên phông nền rèm/tường dịu mắt, phạt nặng vùng chói sáng/xe máy ngoài đường)
        let bgPatch = analyzePatch(
            uCenter: u,
            uHalfWidth: 0.070,
            vMin: vFoot - 0.370,
            vMax: vFoot - 0.170
        )
        let exposureError = abs(bgPatch.meanLuma - 0.56)
        let bgPenalty = bgPatch.glareRatio * 1.65 + bgPatch.meanGrad * 2.6 + bgPatch.stdDev * 1.5 + max(0, exposureError - 0.18) * 1.2
        let backgroundHarmony = min(max(1.0 - bgPenalty, 0.0), 1.0)

        // Điểm tổng hợp ưu tiên góc sàn trống + không bị bàn/quạt chắn + hậu cảnh sạch
        let composite = floorOpenness * 0.28
            + foregroundClearance * 0.28
            + midBodyClearance * 0.24
            + backgroundHarmony * 0.20

        return VisualSpotMetrics(
            floorOpenness: floorOpenness,
            foregroundClearance: foregroundClearance,
            midBodyClearance: midBodyClearance,
            backgroundHarmony: backgroundHarmony,
            compositeScore: min(max(composite, 0.0), 1.0)
        )
    }

    /// Phân tích trực tiếp `CVPixelBuffer` (từ `ARFrame.capturedImage` hoặc ảnh test) tại vị trí ứng viên `normalizedFootPoint`.
    static func evaluateVisualSpotQuality(
        in pixelBuffer: CVPixelBuffer,
        normalizedFootPoint: CGPoint
    ) -> VisualSpotMetrics {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        if planeCount > 0, let baseAddr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let lumaPtr = baseAddr.assumingMemoryBound(to: UInt8.self)
            let isLandscapeSensor = width > height

            return evaluateVisualSpotQuality(normalizedFootPoint: normalizedFootPoint) { u, v in
                // Cảm biến camera sau iOS xuất buffer ở hướng Landscape-Right:
                // điểm màn hình dọc (u, v) ánh xạ sang (sensorX = v, sensorY = 1 - u)
                let sx: Float = isLandscapeSensor ? v : u
                let sy: Float = isLandscapeSensor ? (1.0 - u) : v
                let px = min(max(Int(sx * Float(width - 1)), 0), width - 1)
                let py = min(max(Int(sy * Float(height - 1)), 0), height - 1)
                let luma = lumaPtr[py * bytesPerRow + px]
                return Float(luma) / 255.0
            }
        } else if let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)
            let isLandscapeSensor = width > height

            return evaluateVisualSpotQuality(normalizedFootPoint: normalizedFootPoint) { u, v in
                let sx: Float = isLandscapeSensor ? v : u
                let sy: Float = isLandscapeSensor ? (1.0 - u) : v
                let px = min(max(Int(sx * Float(width - 1)), 0), width - 1)
                let py = min(max(Int(sy * Float(height - 1)), 0), height - 1)
                let offset = py * bytesPerRow + px * 4
                let b = Float(ptr[offset])
                let g = Float(ptr[offset + 1])
                let r = Float(ptr[offset + 2])
                return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            }
        }

        return VisualSpotMetrics(
            floorOpenness: 0.5,
            foregroundClearance: 0.5,
            midBodyClearance: 0.5,
            backgroundHarmony: 0.5,
            compositeScore: 0.5
        )
    }

    /// Tính điểm phạt vật cản 3D (`0...1`) từ đám mây điểm `ARFrame.rawFeaturePoints`:
    /// phát hiện bàn ghế, quạt cây hoặc đồ vật nhô cao trên mặt sàn nằm tại vị trí đứng hoặc chắn trước ống kính.
    static func pointCloudObstaclePenalty(
        candidatePosition: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        floorY: Float,
        featurePoints: [SIMD3<Float>]
    ) -> Float {
        guard !featurePoints.isEmpty else { return 0 }
        let toCand = SIMD2<Float>(
            candidatePosition.x - cameraPosition.x,
            candidatePosition.z - cameraPosition.z
        )
        let candDist = simd_length(toCand)
        guard candDist > 0.4 else { return 0 }
        let rayDir = toCand / candDist

        var obstacleHits = 0
        for pt in featurePoints {
            let heightAboveFloor = pt.y - floorY
            // Chỉ xét các điểm vật thể nhô cao khỏi mặt sàn từ 18cm đến 1.65m (bàn, ghế, quạt, cốc nước trên bàn)
            guard heightAboveFloor >= 0.18 && heightAboveFloor <= 1.65 else { continue }

            let bodyDelta = SIMD2<Float>(pt.x - candidatePosition.x, pt.z - candidatePosition.z)
            if simd_length(bodyDelta) < 0.38 {
                obstacleHits += 2
                continue
            }

            // Kiểm tra hành lang tia nhìn từ camera tới điểm ứng viên
            let rel = SIMD2<Float>(pt.x - cameraPosition.x, pt.z - cameraPosition.z)
            let forwardProj = simd_dot(rel, rayDir)
            if forwardProj > 0.45 && forwardProj < candDist - 0.15 {
                let perpVec = rel - rayDir * forwardProj
                if simd_length(perpVec) < 0.30 {
                    obstacleHits += 1
                }
            }
        }
        return min(Float(obstacleHits) / 18.0, 1.0)
    }

    /// Kiểm tra điểm giao cắt từ `ARRaycastQuery` có thực sự nằm trên mặt sàn hợp lệ dưới chân
    /// người chụp hay không (loại bỏ các điểm bắn nhầm lên mặt bàn cao, tường hoặc quá sát ống kính).
    @MainActor
    static func shouldAcceptFloorRaycastHit(
        hitPosition: SIMD3<Float>,
        cameraTransform: simd_float4x4,
        minimumVerticalDrop: Float = 0.30,
        distanceRange: ClosedRange<Float> = 0.50...6.00
    ) -> Bool {
        let camPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        guard hitPosition.y <= camPos.y - minimumVerticalDrop else { return false }
        let horizontalDelta = SIMD2<Float>(hitPosition.x - camPos.x, hitPosition.z - camPos.z)
        let horizontalDistance = simd_length(horizontalDelta)
        return distanceRange.contains(horizontalDistance)
    }

    /// Chấm điểm mức độ tối ưu của một điểm sàn ứng viên theo khoảng cách vàng (1.8m – 2.5m)
    /// và độ lệch so với trục ngắm. Điểm càng cao (0...1) thì vị trí đứng càng đẹp.
    @MainActor
    static func scoreFloorCandidate(
        hitPosition: SIMD3<Float>,
        cameraTransform: simd_float4x4,
        pose: ShootingPose,
        isExactGeometry: Bool
    ) -> Float {
        let camPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        let delta = SIMD2<Float>(hitPosition.x - camPos.x, hitPosition.z - camPos.z)
        let dist = simd_length(delta)
        let idealDist = idealStandOffDistance(for: pose)
        let distError = abs(dist - idealDist)
        let distanceScore = max(0, 1.0 - distError / 1.50)
        let geometryBonus: Float = isExactGeometry ? 0.25 : 0.0
        return min(1.0, distanceScore + geometryBonus)
    }

    /// Tính góc xoay trục Y để mẫu 3D tự động hướng mặt về phía camera kèm góc xoay 3/4 nghệ thuật nhẹ
    /// (đặc biệt với dáng ngồi, góc xoay nhẹ `12°` giúp thấy rõ chiều sâu đầu gối và tay đặt trên bàn).
    @MainActor
    static func artisticLookAtOrientation(
        from anchorPosition: SIMD3<Float>,
        to cameraPosition: SIMD3<Float>,
        pose: ShootingPose,
        applyArtisticOffset: Bool = false
    ) -> simd_quatf {
        let toCamera = SIMD3<Float>(
            cameraPosition.x - anchorPosition.x,
            0,
            cameraPosition.z - anchorPosition.z
        )
        let baseYaw = atan2(toCamera.x, toCamera.z)
        let defaultThreeQuarter: Float = pose.stance == .seated ? 12.0 : 6.0
        let artisticDegrees = applyArtisticOffset
            ? (abs(pose.spineTilt) > 1 ? Float(pose.spineTilt * 0.6) : defaultThreeQuarter)
            : 0
        let artisticRadians = artisticDegrees * .pi / 180.0
        return simd_quatf(angle: baseYaw + artisticRadians, axis: SIMD3<Float>(0, 1, 0))
    }

    /// Làm mượt chuyển động (Smoothing & Damping) bằng phép nội suy tuyến tính `simd_mix` cho vị trí
    /// và nội suy cầu `simd_slerp` cho góc xoay, giúp mẫu 3D trượt êm ái trên mặt sàn mà không bị giật/teleport.
    @MainActor
    static func smoothTransform(
        currentPosition: SIMD3<Float>,
        targetPosition: SIMD3<Float>,
        currentOrientation: simd_quatf,
        targetOrientation: simd_quatf,
        positionSmoothing: Float = 0.18,
        rotationSmoothing: Float = 0.20
    ) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        let posT = min(max(positionSmoothing, 0.01), 1.0)
        let rotT = min(max(rotationSmoothing, 0.01), 1.0)
        let smoothedPos = simd_mix(
            currentPosition,
            targetPosition,
            SIMD3<Float>(repeating: posT)
        )
        let smoothedRot = simd_slerp(currentOrientation, targetOrientation, rotT)
        return (smoothedPos, simd_normalize(smoothedRot))
    }

    /// Quy đổi độ sáng môi trường thực tế (`ARLightEstimate.ambientIntensity`, chuẩn 1000 lumen = 1.0)
    /// sang hệ số khuếch đại ánh sáng hợp lý cho mẫu 3D để hòa trộn tự nhiên với căn phòng.
    @MainActor
    static func ambientLightFactor(ambientIntensity: Float) -> Float {
        let normalized = ambientIntensity / 1000.0
        return min(max(normalized, 0.45), 1.45)
    }

    /// Tính vị trí `(X, Y, Z)` và góc xoay `orientation` trên mặt sàn thật cho điểm neo AR
    /// từ vị trí/hướng của camera và độ cao mặt sàn `floorY` đo được bằng ARKit.
    ///
    /// - Important: chân người mẫu 3D trong file `.usdz` nằm tại `Y = 0` của hệ toạ độ
    ///   cục bộ `anchor`. Do đó đặt `anchor.position.y = floorY` sẽ ghim khít lòng bàn chân
    ///   của mẫu 3D xuống đúng mặt gạch/sàn nhà thật, chấm dứt hoàn toàn hiện tượng
    ///   "bay lơ lửng".
    @MainActor
    static func floorAnchorTransform(
        cameraTransform: simd_float4x4,
        pose: ShootingPose,
        floorY: Float,
        hitPosition: SIMD3<Float>? = nil
    ) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        let camPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        // Trục nhìn của ARCamera là -Z (cột thứ 3 đảo dấu).
        let rawForward = -SIMD3<Float>(
            cameraTransform.columns.2.x,
            0,
            cameraTransform.columns.2.z
        )
        let forwardLen = simd_length(rawForward)
        let horizForward = forwardLen > 0.001 ? (rawForward / forwardLen) : SIMD3<Float>(0, 0, -1)

        let targetDistance = Float(pose.cameraDistance)
        let anchorPos: SIMD3<Float>
        if let hit = hitPosition {
            let delta = SIMD2<Float>(hit.x - camPos.x, hit.z - camPos.z)
            let hitDist = simd_length(delta)
            if hitDist >= 0.50 && hitDist <= 6.00 {
                anchorPos = SIMD3<Float>(hit.x, floorY, hit.z)
            } else {
                let clampedDist = min(max(hitDist, idealDistanceRange.lowerBound), idealDistanceRange.upperBound)
                let dir = hitDist > 0.001 ? (delta / hitDist) : SIMD2<Float>(horizForward.x, horizForward.z)
                anchorPos = SIMD3<Float>(
                    camPos.x + dir.x * clampedDist,
                    floorY,
                    camPos.z + dir.y * clampedDist
                )
            }
        } else {
            anchorPos = SIMD3<Float>(
                camPos.x + horizForward.x * targetDistance,
                floorY,
                camPos.z + horizForward.z * targetDistance
            )
        }

        let orientation = artisticLookAtOrientation(
            from: anchorPos,
            to: camPos,
            pose: pose,
            applyArtisticOffset: false
        )
        return (anchorPos, orientation)
    }

    /// Tính vị trí, hướng quay 3D và tiêu cự (FOV) cho nhánh `.nonAR` (Simulator / fallback).
    @MainActor
    static func spatialState(
        for pose: ShootingPose,
        pitch: Float = 0,
        yaw: Float = 0,
        roll: Float = 0,
        translationOffset: SIMD3<Float> = .zero,
        zoomFactor: CGFloat = 1.0
    ) -> SpatialState {
        let basePos = position(for: pose)
        let qYaw = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let qPitch = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let qRoll = simd_quatf(angle: -roll, axis: SIMD3<Float>(0, 0, 1))
        let orientation = simd_normalize(qYaw * qPitch * qRoll)

        let armPivot = SIMD3<Float>(0, 0, -0.30)
        let pivotOffset = orientation.act(armPivot) - armPivot

        let clampedZoom = max(Float(zoomFactor), 0.5)
        let baseFOV = Float(ShootingPose.verticalFieldOfView)
        let halfRad = (baseFOV * .pi / 180.0) * 0.5
        let zoomedFOV = (2.0 * atan(tan(halfRad) / clampedZoom)) * (180.0 / .pi)

        return SpatialState(
            position: basePos + pivotOffset + translationOffset,
            orientation: orientation,
            fieldOfViewInDegrees: zoomedFOV
        )
    }
}

/// Mặt phẳng vô hình tại chân mẫu (`OcclusionMaterial()`) — **tắt `receivesDynamicLighting`**
/// để không bao giờ tạo mảng xám chữ nhật cắt ngang màn hình khi kết hợp với 3 đèn `DirectionalLight`.
@MainActor
enum GroundShadowBuilder {
    static let entityName = "ground-shadow-group"

    static func makeFloorShadow(for _: Entity) -> Entity {
        let group = Entity()
        group.name = entityName

        // Dùng OcclusionMaterial() thuần (không bật receivesDynamicLighting) trên diện tích nhỏ dưới đế giày
        // để tránh hoàn toàn lỗi shader RealityKit tô xám toàn bộ tấm plane 3.6m x 3.6m trên iOS 26.
        let catcherMesh = MeshResource.generatePlane(width: 0.35, depth: 0.35)
        let catcherMaterial = OcclusionMaterial()
        let catcherEntity = ModelEntity(mesh: catcherMesh, materials: [catcherMaterial])
        catcherEntity.name = "floor-shadow-catcher"
        group.addChild(catcherEntity)

        return group
    }
}

/// Khung hiển thị người mẫu 3D bán trong suốt neo trực tiếp xuống mặt sàn thật bằng ARKit.
struct TranslucentSceneView<Content: View>: View {
    static func makeTestLights() -> [Entity] { SceneLighting.make() }

    let pose: ShootingPose
    let metrics: FigureMetrics
    let distance: CGFloat
    var zoomFactor: CGFloat = 1.0
    let isAligned: Bool
    var isTemplateVisible: Bool = true
    var isAppActive: Bool = true
    var cameraService: CameraService? = nil
    /// Ghép thêm nội dung SwiftUI lên trên, dùng cho vòng tròn đếm ngược.
    @ViewBuilder var overlay: Content

    var body: some View {
        TranslucentARViewRepresentable(
            pose: pose,
            metrics: metrics,
            distance: distance,
            zoomFactor: zoomFactor,
            cameraService: cameraService,
            cameraPosition: cameraService?.position ?? .back,
            floorTapID: cameraService?.floorAnchorTapID,
            floorTapPoint: cameraService?.floorAnchorTapPoint,
            isAligned: isAligned,
            isTemplateVisible: isTemplateVisible,
            isAppActive: isAppActive
        )
        .allowsHitTesting(false)
        .overlay(overlay.opacity(isTemplateVisible ? 1 : 0))
    }
}

// MARK: - Scene Host (ARKit Smart Auto-Placement + Lerp/Slerp Damping + Occlusion Shadow Receiver)

private struct TranslucentARViewRepresentable: UIViewRepresentable {
    let pose: ShootingPose
    let metrics: FigureMetrics
    let distance: CGFloat
    let zoomFactor: CGFloat
    let cameraService: CameraService?
    let cameraPosition: AVCaptureDevice.Position
    let floorTapID: UUID?
    let floorTapPoint: CGPoint?
    let isAligned: Bool
    let isTemplateVisible: Bool
    let isAppActive: Bool

    @MainActor
    final class Coordinator: NSObject {
        weak var arView: ARView?
        weak var cameraService: CameraService?
        var anchor: AnchorEntity?
        var rigContainer: Entity?
        var root: Entity?
        var shadowGroup: Entity?
        var lights: [Entity] = []
        var camera: PerspectiveCamera?
        var currentPoseID: String?
        var currentMetrics: FigureMetrics?
        var currentPose: ShootingPose = .seatedStraight
        var currentZoomFactor: CGFloat = 1.0
        var isTemplateVisible: Bool = true
        var isAppActive: Bool = true
        var currentCameraPosition: AVCaptureDevice.Position = .back
        var lastHandledTapID: UUID?

        /// Trạng thái neo mặt sàn thực và làm mượt chuyển động (Smoothing & Damping).
        var isUsingWorldTracking = false
        var isSessionPausedForBackground = false
        var isLockedToRealFloor = false
        var hasInitialPlacement = false
        var lockedFloorY: Float = 0
        var lastCameraTransform: simd_float4x4 = matrix_identity_float4x4
        var targetAnchorPosition: SIMD3<Float> = .zero
        var targetAnchorOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        var stableEstimateCount = 0
        var unanchoredFrameCount = 0
        var isUserPinned = false
        var lastEstimatedFloorY: Float?
        var sceneUpdateSubscription: Cancellable?

        #if !targetEnvironment(simulator)
        var trackedRaycast: ARTrackedRaycast?
        weak var coachingOverlay: ARCoachingOverlayView?
        #endif

        // MARK: - ARKit World Tracking Lifecycle

        func startWorldTracking(in view: ARView) {
            arView = view
            guard GuideCamera.supportsRealSpaceAR, currentCameraPosition == .back else { return }
            #if !targetEnvironment(simulator)
            camera?.removeFromParent()
            camera = nil
            if view.cameraMode != .ar {
                view.cameraMode = .ar
            }
            view.isOpaque = true
            view.environment.background = .cameraFeed()
            coachingOverlay?.isHidden = false

            isUsingWorldTracking = true
            isSessionPausedForBackground = false
            isLockedToRealFloor = false
            hasInitialPlacement = false
            isUserPinned = false
            stableEstimateCount = 0
            unanchoredFrameCount = 0
            lastEstimatedFloorY = nil
            trackedRaycast?.stopTracking()
            trackedRaycast = nil

            if let shadowGroup, shadowGroup.parent == nil {
                rigContainer?.addChild(shadowGroup)
            }
            updateRigVisibility()

            cameraService?.setExternalARActive(true)
            cameraService?.setFloorLocked(false)
            view.session.delegate = self

            view.environment.sceneUnderstanding.options.insert(.receivesLighting)

            // Đăng ký vòng lặp render 60Hz của RealityKit để nội suy mượt vị trí & góc xoay (Lerp / Slerp)
            sceneUpdateSubscription?.cancel()
            sceneUpdateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.stepSmoothTransform()
            }

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            config.isLightEstimationEnabled = true
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            }
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            #endif
        }

        func switchToNonAROverlay(in view: ARView) {
            stopTracking()
            #if !targetEnvironment(simulator)
            coachingOverlay?.setActive(false, animated: false)
            coachingOverlay?.isHidden = true
            if view.cameraMode != .nonAR {
                view.cameraMode = .nonAR
            }
            #endif
            view.isOpaque = false
            view.backgroundColor = .clear
            view.environment.background = .color(.clear)
            shadowGroup?.removeFromParent()

            if let anchor {
                anchor.position = .zero
                anchor.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                if camera == nil {
                    let cam = PerspectiveCamera()
                    cam.name = GuideCamera.entityName
                    anchor.addChild(cam)
                    camera = cam
                }
            }
            updateRigVisibility()
            applyFallbackCameraTransform()
        }

        func setAppActive(_ active: Bool, in view: ARView) {
            guard isAppActive != active else { return }
            isAppActive = active
            #if !targetEnvironment(simulator)
            if !active {
                if isUsingWorldTracking {
                    isSessionPausedForBackground = true
                    trackedRaycast?.stopTracking()
                    trackedRaycast = nil
                    view.session.pause()
                }
            } else if isSessionPausedForBackground && GuideCamera.supportsRealSpaceAR && currentCameraPosition == .back {
                isSessionPausedForBackground = false
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal]
                config.environmentTexturing = .automatic
                config.isLightEstimationEnabled = true
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                    config.sceneReconstruction = .meshWithClassification
                }
                view.session.run(config)
            }
            #endif
        }

        func setupCoachingOverlay(in view: ARView) {
            #if !targetEnvironment(simulator)
            guard GuideCamera.supportsRealSpaceAR else { return }
            let overlay = ARCoachingOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.session = view.session
            overlay.goal = .horizontalPlane
            overlay.activatesAutomatically = true
            overlay.delegate = self
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: view.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            coachingOverlay = overlay
            #endif
        }

        func stopTracking() {
            sceneUpdateSubscription?.cancel()
            sceneUpdateSubscription = nil
            if isUsingWorldTracking {
                #if !targetEnvironment(simulator)
                trackedRaycast?.stopTracking()
                trackedRaycast = nil
                arView?.session.pause()
                #endif
                cameraService?.setFloorLocked(false)
                cameraService?.setExternalARActive(false)
                isUsingWorldTracking = false
            }
        }

        func updateRigVisibility() {
            guard let rigContainer else { return }
            if isUsingWorldTracking {
                rigContainer.isEnabled = isTemplateVisible && isLockedToRealFloor
            } else {
                rigContainer.isEnabled = isTemplateVisible
            }
        }

        /// Nội suy mượt vị trí (`simd_mix`) và góc xoay (`simd_slerp`) ở mỗi frame để mẫu 3D
        /// trượt êm vào vị trí mặt sàn thật mà không bị giật/teleport.
        private func stepSmoothTransform() {
            guard isUsingWorldTracking, isLockedToRealFloor, let anchor else { return }
            let smoothed = GuideCamera.smoothTransform(
                currentPosition: anchor.position,
                targetPosition: targetAnchorPosition,
                currentOrientation: anchor.orientation,
                targetOrientation: targetAnchorOrientation,
                positionSmoothing: 0.18,
                rotationSmoothing: 0.20
            )
            anchor.position = smoothed.position
            anchor.orientation = smoothed.orientation
        }

        /// Khi người dùng đổi tư thế (ví dụ từ Ngồi -> Đứng), tự động điều chỉnh mượt cự ly chuẩn
        /// và góc xoay 3/4 ngay trên mặt sàn hiện tại để mẫu luôn vừa vặn trong khung ngắm.
        func adjustPlacementForPoseChange() {
            guard isUsingWorldTracking, isLockedToRealFloor else { return }
            let camPos = SIMD3<Float>(
                lastCameraTransform.columns.3.x,
                lastCameraTransform.columns.3.y,
                lastCameraTransform.columns.3.z
            )
            let delta = SIMD2<Float>(
                targetAnchorPosition.x - camPos.x,
                targetAnchorPosition.z - camPos.z
            )
            let dist = simd_length(delta)
            let idealDist = GuideCamera.idealStandOffDistance(for: currentPose)
            if dist > 0.1 {
                let dir = delta / dist
                targetAnchorPosition = SIMD3<Float>(
                    camPos.x + dir.x * idealDist,
                    lockedFloorY,
                    camPos.z + dir.y * idealDist
                )
            }
            targetAnchorOrientation = GuideCamera.artisticLookAtOrientation(
                from: targetAnchorPosition,
                to: camPos,
                pose: currentPose,
                applyArtisticOffset: true
            )
        }

        // MARK: - Smart Auto-Placement (Rule of Thirds + Ideal Depth 1.8m-2.5m + Auto Face Camera)

        func updateWorldFloorAnchor(
            cameraTransform: simd_float4x4,
            detectedFloorY: Float?,
            ambientIntensity: Float?
        ) {
            guard isUsingWorldTracking, let view = arView, let anchor else { return }
            lastCameraTransform = cameraTransform

            if let intensity = ambientIntensity {
                applyAmbientLighting(ambientIntensity: intensity, in: view)
            }

            #if !targetEnvironment(simulator)
            let camPos = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            let rawForward = -SIMD3<Float>(
                cameraTransform.columns.2.x,
                0,
                cameraTransform.columns.2.z
            )
            let forwardLen = simd_length(rawForward)
            let horizForward = forwardLen > 0.001 ? (rawForward / forwardLen) : SIMD3<Float>(0, 0, -1)

            // Khi đã khóa vào mặt sàn thật:
            // - Luôn tinh chỉnh mượt cao độ sàn Y từ ARPlaneAnchor / raycast
            // - Nếu người dùng lia máy sang góc mới (lệch > 14° khỏi hướng tới mẫu hoặc bước đi > 0.45m)
            //   và chưa ghim thủ công (isUserPinned == false), tự động quét lại khung hình để tìm góc đứng thoáng đẹp nhất!
            if isLockedToRealFloor {
                if let exactFloorY = detectedFloorY, abs(exactFloorY - lockedFloorY) < 0.45 {
                    lockedFloorY += (exactFloorY - lockedFloorY) * 0.22
                    targetAnchorPosition.y = lockedFloorY
                }

                if !isUserPinned {
                    let toAnchor = SIMD3<Float>(
                        targetAnchorPosition.x - camPos.x,
                        0,
                        targetAnchorPosition.z - camPos.z
                    )
                    let horizDist = simd_length(toAnchor)
                    let dirToAnchor = horizDist > 0.001 ? (toAnchor / horizDist) : horizForward
                    let cosAngle = simd_dot(horizForward, dirToAnchor)
                    let minDist: Float = currentPose.stance == .standing ? 2.45 : 2.10
                    let maxDist: Float = currentPose.stance == .standing ? 3.75 : 3.30
                    let outOfDistanceBand = horizDist < minDist - 0.25 || horizDist > maxDist + 0.35

                    // Kiểm tra nếu hình chiếu chân mẫu trên màn hình bị trôi ra ngoài vùng sàn đẹp (u: 0.26..0.74, v: 0.54..0.75)
                    var isProjectedOutOfSweetZone = false
                    if view.bounds.width > 0, view.bounds.height > 0,
                       let screenPt = view.project(targetAnchorPosition) {
                        let normU = screenPt.x / view.bounds.width
                        let normV = screenPt.y / view.bounds.height
                        if normU < 0.26 || normU > 0.74 || normV < 0.54 || normV > 0.75 {
                            isProjectedOutOfSweetZone = true
                        }
                    }

                    if cosAngle < 0.968 || outOfDistanceBand || isProjectedOutOfSweetZone {
                        if let bestHit = findBestRuleOfThirdsFloorHit(
                            in: view,
                            cameraTransform: cameraTransform,
                            allowEstimated: true,
                            knownFloorY: lockedFloorY
                        ) {
                            lockToRealFloor(
                                in: view,
                                cameraTransform: cameraTransform,
                                floorY: lockedFloorY,
                                hitPosition: bestHit.position,
                                raycastQuery: bestHit.query,
                                isUserTap: false
                            )
                            return
                        }
                    }
                }

                targetAnchorOrientation = GuideCamera.artisticLookAtOrientation(
                    from: targetAnchorPosition,
                    to: camPos,
                    pose: currentPose,
                    applyArtisticOffset: true
                )
                return
            }

            // 1. Ưu tiên cao nhất: Quét 15 điểm trên mặt phẳng sàn thật đã được ARKit xác nhận để chọn góc đẹp nhất
            if let bestHit = findBestRuleOfThirdsFloorHit(
                in: view,
                cameraTransform: cameraTransform,
                allowEstimated: false,
                knownFloorY: detectedFloorY
            ) {
                let floorY = detectedFloorY ?? bestHit.position.y
                lockToRealFloor(
                    in: view,
                    cameraTransform: cameraTransform,
                    floorY: floorY,
                    hitPosition: bestHit.position,
                    raycastQuery: bestHit.query,
                    isUserTap: false
                )
                return
            }

            // 2. Nếu ARKit đang quét sàn và trả về `.estimatedPlane` ổn định liên tiếp >= 3 frame (sai số < 3cm)
            if let estHit = findBestRuleOfThirdsFloorHit(
                in: view,
                cameraTransform: cameraTransform,
                allowEstimated: true,
                knownFloorY: detectedFloorY
            ) {
                if let prevY = lastEstimatedFloorY, abs(estHit.position.y - prevY) < 0.03 {
                    stableEstimateCount += 1
                } else {
                    stableEstimateCount = 1
                }
                lastEstimatedFloorY = estHit.position.y

                if stableEstimateCount >= 3 {
                    let floorY = detectedFloorY ?? estHit.position.y
                    lockToRealFloor(
                        in: view,
                        cameraTransform: cameraTransform,
                        floorY: floorY,
                        hitPosition: estHit.position,
                        raycastQuery: estHit.query,
                        isUserTap: false
                    )
                    return
                }
            }

            // 3. Nếu sàn gạch/bê tông bóng ít vân khiến ARKit chưa kịp tạo plane sau 12 frame (~0.2s),
            // phân tích ngay khung hình để chọn góc thoáng nhất trên mặt sàn ước lượng (camY - 1.25m)
            unanchoredFrameCount += 1
            if unanchoredFrameCount >= 12 {
                let fallbackFloorY = detectedFloorY ?? (camPos.y - 1.25)
                if let bestVisualSpot = findBestRuleOfThirdsFloorHit(
                    in: view,
                    cameraTransform: cameraTransform,
                    allowEstimated: true,
                    knownFloorY: fallbackFloorY
                ) {
                    lockToRealFloor(
                        in: view,
                        cameraTransform: cameraTransform,
                        floorY: fallbackFloorY,
                        hitPosition: bestVisualSpot.position,
                        raycastQuery: bestVisualSpot.query,
                        isUserTap: false
                    )
                } else {
                    let fallbackDist: Float = currentPose.stance == .standing ? 2.85 : 2.35
                    let fallbackHit = SIMD3<Float>(
                        camPos.x + horizForward.x * fallbackDist,
                        fallbackFloorY,
                        camPos.z + horizForward.z * fallbackDist
                    )
                    lockToRealFloor(
                        in: view,
                        cameraTransform: cameraTransform,
                        floorY: fallbackFloorY,
                        hitPosition: fallbackHit,
                        raycastQuery: nil,
                        isUserTap: false
                    )
                }
            }
            #else
            _ = anchor
            _ = cameraTransform
            _ = detectedFloorY
            #endif
        }

        /// Tự động tìm góc đứng đẹp nhất trong khung hình (khi `point == .zero` từ nút "Góc đẹp / Đặt lại mẫu")
        /// hoặc đặt mẫu tại đúng vị trí sàn nơi người dùng chạm tay trên màn hình (`point != .zero`).
        func reanchorAtScreenPoint(_ point: CGPoint) {
            #if !targetEnvironment(simulator)
            guard isUsingWorldTracking, let view = arView,
                  let frame = view.session.currentFrame else { return }
            let camTransform = frame.camera.transform
            lastCameraTransform = camTransform

            let camPos = SIMD3<Float>(
                camTransform.columns.3.x,
                camTransform.columns.3.y,
                camTransform.columns.3.z
            )
            let rawForward = -SIMD3<Float>(
                camTransform.columns.2.x,
                0,
                camTransform.columns.2.z
            )
            let forwardLen = simd_length(rawForward)
            let horizForward = forwardLen > 0.001 ? (rawForward / forwardLen) : SIMD3<Float>(0, 0, -1)
            let currentFloorY = isLockedToRealFloor ? lockedFloorY : (camPos.y - 1.25)

            // Trường hợp 1: Người dùng bấm nút "Tìm góc đẹp / Đặt lại mẫu" (point == .zero)
            // -> Bỏ ghim thủ công và chạy thuật toán quét 15 điểm để chọn góc thoáng đẹp nhất trong khung!
            if point == .zero {
                isUserPinned = false
                if let bestHit = findBestRuleOfThirdsFloorHit(
                    in: view,
                    cameraTransform: camTransform,
                    allowEstimated: true,
                    knownFloorY: currentFloorY
                ) {
                    lockToRealFloor(
                        in: view,
                        cameraTransform: camTransform,
                        floorY: bestHit.position.y,
                        hitPosition: bestHit.position,
                        raycastQuery: bestHit.query,
                        isUserTap: false
                    )
                    return
                }
            } else {
                // Trường hợp 2: Người dùng chạm trực tiếp vào một vị trí trên sàn nhà trong khung ngắm
                isUserPinned = true
                if let hit = performHorizontalRaycast(in: view, at: point, allowEstimated: true),
                   GuideCamera.shouldAcceptFloorRaycastHit(
                       hitPosition: hit.position,
                       cameraTransform: camTransform,
                       minimumVerticalDrop: 0.20
                   ) {
                    lockToRealFloor(
                        in: view,
                        cameraTransform: camTransform,
                        floorY: hit.position.y,
                        hitPosition: hit.position,
                        raycastQuery: hit.query,
                        isUserTap: true
                    )
                    return
                }

                if let ray = view.ray(through: point), ray.direction.y < -0.03 {
                    let t = (currentFloorY - ray.origin.y) / ray.direction.y
                    if t >= 1.20 && t <= 5.50 {
                        let hitPos = ray.origin + ray.direction * t
                        lockToRealFloor(
                            in: view,
                            cameraTransform: camTransform,
                            floorY: currentFloorY,
                            hitPosition: hitPos,
                            raycastQuery: nil,
                            isUserTap: true
                        )
                        return
                    }
                }
            }

            // Fallback an toàn
            let fallbackDist: Float = currentPose.stance == .standing ? 2.85 : 2.35
            let centerHit = SIMD3<Float>(
                camPos.x + horizForward.x * fallbackDist,
                currentFloorY,
                camPos.z + horizForward.z * fallbackDist
            )
            lockToRealFloor(
                in: view,
                cameraTransform: camTransform,
                floorY: currentFloorY,
                hitPosition: centerHit,
                raycastQuery: nil,
                isUserTap: false
            )
            #endif
        }

        #if !targetEnvironment(simulator)
        private struct RaycastHit {
            let position: SIMD3<Float>
            let query: ARRaycastQuery?
            let isExactGeometry: Bool
            let score: Float
        }

        /// Quét 15 điểm ứng viên trên dải sàn mở (`u ∈ 0.36...0.64, v ∈ 0.65...0.72`),
        /// kết hợp phân tích thị giác (tránh bàn tiền cảnh, quạt cây, xe cộ chói sáng; ưu tiên sàn trống & phông nền sạch)
        /// cùng đám mây điểm 3D của ARKit để chọn ra **góc đứng đẹp nhất trong khung hình**.
        private func findBestRuleOfThirdsFloorHit(
            in view: ARView,
            cameraTransform: simd_float4x4,
            allowEstimated: Bool,
            knownFloorY: Float? = nil
        ) -> RaycastHit? {
            let w = view.bounds.width > 0 ? view.bounds.width : 390
            let h = view.bounds.height > 0 ? view.bounds.height : 844
            let frame = view.session.currentFrame
            let pixelBuffer = frame?.capturedImage
            let featurePoints: [SIMD3<Float>] = frame?.rawFeaturePoints?.points ?? []
            let camPos = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            var bestHit: RaycastHit?
            var bestScore: Float = -1

            for normPt in GuideCamera.compositionCandidateNormalizedPoints {
                let screenPt = CGPoint(x: normPt.x * w, y: normPt.y * h)
                var candidateHit: (position: SIMD3<Float>, query: ARRaycastQuery?, isExact: Bool)?

                if let hit = performHorizontalRaycast(
                    in: view,
                    at: screenPt,
                    allowEstimated: allowEstimated
                ), GuideCamera.shouldAcceptFloorRaycastHit(
                    hitPosition: hit.position,
                    cameraTransform: cameraTransform
                ) {
                    candidateHit = (hit.position, hit.query, hit.isExactGeometry)
                } else if let floorY = knownFloorY,
                          let ray = view.ray(through: screenPt),
                          ray.direction.y < -0.04 {
                    let t = (floorY - ray.origin.y) / ray.direction.y
                    if t >= 1.60 && t <= 5.20 {
                        let pos = ray.origin + ray.direction * t
                        if GuideCamera.shouldAcceptFloorRaycastHit(
                            hitPosition: pos,
                            cameraTransform: cameraTransform
                        ) {
                            candidateHit = (pos, nil, false)
                        }
                    }
                }

                guard let resolved = candidateHit else { continue }

                // 1. Điểm chất lượng thị giác của góc đứng (sàn trống + không vướng bàn tiền cảnh/quạt + nền sạch)
                let visualScore: Float
                if let pb = pixelBuffer {
                    visualScore = GuideCamera.evaluateVisualSpotQuality(
                        in: pb,
                        normalizedFootPoint: normPt
                    ).compositeScore
                } else {
                    visualScore = 0.65
                }

                // 2. Điểm phạt vật cản 3D từ đám mây điểm ARKit (bàn ghế, vật thể nhô cao trên sàn)
                let obstaclePenalty = GuideCamera.pointCloudObstaclePenalty(
                    candidatePosition: resolved.position,
                    cameraPosition: camPos,
                    floorY: resolved.position.y,
                    featurePoints: featurePoints
                )

                // 3. Điểm khoảng cách & hình học mặt phẳng ARKit
                let geomScore = GuideCamera.scoreFloorCandidate(
                    hitPosition: resolved.position,
                    cameraTransform: cameraTransform,
                    pose: currentPose,
                    isExactGeometry: resolved.isExact
                )

                // 4. Điểm bố cục nhiếp ảnh: ưu tiên đường 1/3 dưới (v = 0.68) và các trục 1/3 hoặc trung tâm (u = 0.42, 0.50, 0.58)
                let rowBonus: Float = abs(Float(normPt.y) - 0.68) < 0.015 ? 0.04 : 0.0
                let colBonus: Float = (abs(Float(normPt.x) - 0.42) < 0.03 || abs(Float(normPt.x) - 0.58) < 0.03 || abs(Float(normPt.x) - 0.50) < 0.03) ? 0.04 : 0.0

                let totalScore = visualScore * 0.56
                    + (1.0 - obstaclePenalty) * 0.22
                    + geomScore * 0.14
                    + rowBonus + colBonus

                if totalScore > bestScore {
                    bestScore = totalScore
                    bestHit = RaycastHit(
                        position: resolved.position,
                        query: resolved.query,
                        isExactGeometry: resolved.isExact,
                        score: totalScore
                    )
                }
            }
            return bestHit
        }

        private func performHorizontalRaycast(
            in view: ARView,
            at point: CGPoint,
            allowEstimated: Bool
        ) -> RaycastHit? {
            let targets: [ARRaycastQuery.Target] = allowEstimated
                ? [.existingPlaneGeometry, .existingPlaneInfinite, .estimatedPlane]
                : [.existingPlaneGeometry, .existingPlaneInfinite]
            for target in targets {
                guard let query = view.makeRaycastQuery(
                    from: point,
                    allowing: target,
                    alignment: .horizontal
                ) else { continue }
                let results = view.session.raycast(query)
                if let first = results.first {
                    let col = first.worldTransform.columns.3
                    return RaycastHit(
                        position: SIMD3<Float>(col.x, col.y, col.z),
                        query: query,
                        isExactGeometry: target == .existingPlaneGeometry,
                        score: 0
                    )
                }
            }
            return nil
        }

        private func lockToRealFloor(
            in view: ARView,
            cameraTransform: simd_float4x4,
            floorY: Float,
            hitPosition: SIMD3<Float>,
            raycastQuery: ARRaycastQuery?,
            isUserTap: Bool
        ) {
            guard let anchor else { return }

            let camPos = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            let rawForward = -SIMD3<Float>(
                cameraTransform.columns.2.x,
                0,
                cameraTransform.columns.2.z
            )
            let forwardLen = simd_length(rawForward)
            let horizForward = forwardLen > 0.001 ? (rawForward / forwardLen) : SIMD3<Float>(0, 0, -1)

            // Giữ đúng hướng tia ngắm của góc đứng đẹp nhất (`hitPosition`) mà thuật toán vừa chọn được trên mặt sàn thật!
            // Giới hạn khoảng cách trong dải phối cảnh tự nhiên (2.55m - 3.65m cho dáng đứng; 2.15m - 3.20m cho dáng ngồi)
            // để chân mẫu luôn đậu trên vùng sàn trống (v ≈ 0.65..0.72), không bao giờ tràn xuống mặt bàn tiền cảnh.
            let delta = SIMD2<Float>(hitPosition.x - camPos.x, hitPosition.z - camPos.z)
            let dist = simd_length(delta)
            let dir = dist > 0.001 ? (delta / dist) : SIMD2<Float>(horizForward.x, horizForward.z)

            let minDist: Float = isUserTap ? 1.45 : (currentPose.stance == .standing ? 2.55 : 2.15)
            let maxDist: Float = isUserTap ? 4.30 : (currentPose.stance == .standing ? 3.65 : 3.20)
            let clampedDist = min(max(dist, minDist), maxDist)
            let effectiveHit = SIMD3<Float>(
                camPos.x + dir.x * clampedDist,
                floorY,
                camPos.z + dir.y * clampedDist
            )

            let placement = GuideCamera.floorAnchorTransform(
                cameraTransform: cameraTransform,
                pose: currentPose,
                floorY: floorY,
                hitPosition: effectiveHit
            )
            targetAnchorPosition = placement.position
            targetAnchorOrientation = GuideCamera.artisticLookAtOrientation(
                from: placement.position,
                to: camPos,
                pose: currentPose,
                applyArtisticOffset: true
            )

            if !hasInitialPlacement {
                anchor.position = targetAnchorPosition
                anchor.orientation = targetAnchorOrientation
                hasInitialPlacement = true
            }

            lockedFloorY = floorY
            isLockedToRealFloor = true
            updateRigVisibility()
            cameraService?.setFloorLocked(true)

            // Khởi tạo ARTrackedRaycast để ARKit liên tục hiệu chỉnh cao độ mặt sàn theo thời gian thực
            trackedRaycast?.stopTracking()
            if let query = raycastQuery {
                trackedRaycast = view.session.trackedRaycast(query) { [weak self] results in
                    guard let first = results.first else { return }
                    let refinedY = first.worldTransform.columns.3.y
                    Task { @MainActor [weak self] in
                        guard let self, self.isLockedToRealFloor else { return }
                        if abs(refinedY - self.lockedFloorY) < 0.30 {
                            self.lockedFloorY += (refinedY - self.lockedFloorY) * 0.25
                            self.targetAnchorPosition.y = self.lockedFloorY
                        }
                    }
                }
            }
        }
        #endif

        private func applyAmbientLighting(ambientIntensity: Float, in view: ARView) {
            let factor = GuideCamera.ambientLightFactor(ambientIntensity: ambientIntensity)
            view.environment.lighting.intensityExponent = log2(max(factor, 0.25))
            SceneLighting.updateIntensity(in: lights, factor: factor)
        }

        func applyFallbackCameraTransform() {
            guard !isUsingWorldTracking, let camera else { return }
            let state = GuideCamera.spatialState(for: currentPose, zoomFactor: currentZoomFactor)
            camera.position = state.position
            camera.orientation = state.orientation
            camera.camera.fieldOfViewInDegrees = state.fieldOfViewInDegrees
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let useRealAR = GuideCamera.supportsRealSpaceAR && cameraPosition == .back
        #if targetEnvironment(simulator)
        let view = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.isOpaque = false
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        #else
        let view = ARView(
            frame: .zero,
            cameraMode: useRealAR ? .ar : .nonAR,
            automaticallyConfigureSession: false
        )
        view.isOpaque = useRealAR
        view.backgroundColor = .clear
        if useRealAR {
            view.environment.background = .cameraFeed()
        } else {
            view.environment.background = .color(.clear)
        }
        #endif
        // Tắt toàn bộ thông số debug trên màn hình (FPS, showStatistics, world origin, wireframe) chuẩn App Store
        view.debugOptions = []
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)

        let anchor = AnchorEntity(world: .zero)
        let rigContainer = Entity()
        rigContainer.name = "guide-rig-container"
        // Trên thiết bị thực chạy ARKit, ẩn mẫu 3D cho tới khi khoá được mặt sàn thật
        rigContainer.isEnabled = !useRealAR && isTemplateVisible
        anchor.addChild(rigContainer)

        let scene = GuideSceneBuilder.build(pose: pose, metrics: metrics)
        FigureMaterial.apply(to: scene, isAligned: isAligned)
        rigContainer.addChild(scene)

        let shadowGroup = GroundShadowBuilder.makeFloorShadow(for: scene)
        if useRealAR {
            rigContainer.addChild(shadowGroup)
        }

        if !useRealAR {
            let camera = PerspectiveCamera()
            camera.name = GuideCamera.entityName
            let initialState = GuideCamera.spatialState(for: pose, zoomFactor: zoomFactor)
            camera.camera.fieldOfViewInDegrees = initialState.fieldOfViewInDegrees
            camera.position = initialState.position
            camera.orientation = initialState.orientation
            anchor.addChild(camera)
            context.coordinator.camera = camera
        }

        let sceneLights = SceneLighting.make()
        for light in sceneLights { rigContainer.addChild(light) }
        view.scene.addAnchor(anchor)

        let coordinator = context.coordinator
        coordinator.arView = view
        coordinator.cameraService = cameraService
        coordinator.anchor = anchor
        coordinator.rigContainer = rigContainer
        coordinator.root = scene
        coordinator.shadowGroup = shadowGroup
        coordinator.lights = sceneLights
        coordinator.currentPoseID = pose.id
        coordinator.currentMetrics = metrics
        coordinator.currentPose = pose
        coordinator.currentZoomFactor = zoomFactor
        coordinator.isTemplateVisible = isTemplateVisible
        coordinator.currentCameraPosition = cameraPosition
        coordinator.isAppActive = isAppActive

        if GuideCamera.supportsRealSpaceAR {
            coordinator.setupCoachingOverlay(in: view)
            if useRealAR {
                coordinator.startWorldTracking(in: view)
            }
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.cameraService = cameraService
        coordinator.currentPose = pose
        coordinator.currentZoomFactor = zoomFactor
        coordinator.isTemplateVisible = isTemplateVisible

        // Quản lý vòng đời Camera/AR khi ứng dụng ẩn (.background) hoặc hoạt động lại (.active)
        coordinator.setAppActive(isAppActive, in: view)

        // Xử lý lật Camera trước / sau trên thiết bị thực hỗ trợ ARKit
        if coordinator.currentCameraPosition != cameraPosition {
            coordinator.currentCameraPosition = cameraPosition
            if GuideCamera.supportsRealSpaceAR {
                if cameraPosition == .back && isAppActive {
                    coordinator.startWorldTracking(in: view)
                } else {
                    coordinator.switchToNonAROverlay(in: view)
                }
            }
        }

        coordinator.updateRigVisibility()

        // Nếu người dùng chạm vào sàn để đặt lại vị trí mẫu 3D (Tap-to-Place)
        if let tapID = floorTapID, tapID != coordinator.lastHandledTapID, let tapPoint = floorTapPoint {
            coordinator.lastHandledTapID = tapID
            coordinator.reanchorAtScreenPoint(tapPoint)
        }

        // Khi người dùng đổi tư thế hoặc đổi chiều cao:
        // Giải phóng hoàn toàn thực thể 3D cũ (mesh, material, children) khỏi bộ nhớ trước khi nạp mẫu mới
        // để chống tràn RAM, sau đó căn chỉnh lại khoảng cách/góc xoay 3/4 ngay trên mặt sàn thật.
        if coordinator.currentPoseID != pose.id || coordinator.currentMetrics != metrics {
            if let rigContainer = coordinator.rigContainer {
                GuideSceneBuilder.releaseEntityHierarchy(coordinator.root)
                GuideSceneBuilder.releaseEntityHierarchy(coordinator.shadowGroup)
                coordinator.root = nil
                coordinator.shadowGroup = nil

                let newScene = GuideSceneBuilder.build(pose: pose, metrics: metrics)
                FigureMaterial.apply(to: newScene, isAligned: isAligned)
                rigContainer.addChild(newScene)

                let newShadow = GroundShadowBuilder.makeFloorShadow(for: newScene)
                if coordinator.isUsingWorldTracking {
                    rigContainer.addChild(newShadow)
                }

                coordinator.root = newScene
                coordinator.shadowGroup = newShadow
            }
            coordinator.currentPoseID = pose.id
            coordinator.currentMetrics = metrics
            if coordinator.isUsingWorldTracking {
                coordinator.adjustPlacementForPoseChange()
            } else {
                coordinator.applyFallbackCameraTransform()
            }
            return
        }

        if !coordinator.isUsingWorldTracking {
            coordinator.applyFallbackCameraTransform()
        }

        // Cập nhật màu lớp da khi trạng thái đạt/không đạt đổi.
        guard let root = coordinator.root else { return }
        FigureMaterial.apply(to: root, isAligned: isAligned)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stopTracking()
        GuideSceneBuilder.releaseEntityHierarchy(coordinator.root)
        GuideSceneBuilder.releaseEntityHierarchy(coordinator.shadowGroup)
        for light in coordinator.lights {
            GuideSceneBuilder.releaseEntityHierarchy(light)
        }
        coordinator.lights.removeAll()
        coordinator.root = nil
        coordinator.shadowGroup = nil
        coordinator.anchor?.removeFromParent()
        coordinator.anchor = nil
    }
}

#if !targetEnvironment(simulator)
extension TranslucentARViewRepresentable.Coordinator: ARSessionDelegate, ARCoachingOverlayViewDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let camTransform = frame.camera.transform
        let ambientIntensity = frame.lightEstimate.map { Float($0.ambientIntensity) }

        // Tìm độ cao Y thấp nhất của các mặt phẳng ngang (sàn nhà) mà ARKit đã phát hiện
        let camY = camTransform.columns.3.y
        var lowestPlaneY: Float?
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { continue }
            #if !os(macOS)
            if case .ceiling = plane.classification { continue }
            if case .table = plane.classification { continue }
            if case .seat = plane.classification { continue }
            #endif
            let py = plane.transform.columns.3.y
            if py < camY - 0.30 {
                if let cur = lowestPlaneY {
                    lowestPlaneY = min(cur, py)
                } else {
                    lowestPlaneY = py
                }
            }
        }

        nonisolated(unsafe) let capturedPixelBuffer = pixelBuffer
        let confirmedFloorY = lowestPlaneY

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cameraService?.ingestARPixelBuffer(capturedPixelBuffer)
            self.updateWorldFloorAnchor(
                cameraTransform: camTransform,
                detectedFloorY: confirmedFloorY,
                ambientIntensity: ambientIntensity
            )
        }
    }

    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        updateRigVisibility()
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        updateRigVisibility()
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        guard let view = arView else { return }
        startWorldTracking(in: view)
    }
}
#endif

// MARK: - Ánh sáng

/// Ba đèn kiểu studio cho cảnh hướng dẫn, tự động điều chỉnh cường độ theo `ARLightEstimate` của phòng thật.
@MainActor
enum SceneLighting {
    private static let baseKeyIntensity: Float = 900
    private static let baseFillIntensity: Float = 320
    private static let baseRimIntensity: Float = 950

    static func make() -> [Entity] {
        var lights: [Entity] = []

        let key = DirectionalLight()
        key.name = "light-key"
        key.light.intensity = baseKeyIntensity
        key.light.color = .white
        key.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0))
        key.position = SIMD3<Float>(-1.2, 2.2, 1.4)
        lights.append(key)

        let fill = DirectionalLight()
        fill.name = "light-fill"
        fill.light.intensity = baseFillIntensity
        fill.light.color = UIColor(white: 0.94, alpha: 1)
        fill.orientation = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(0, 1, 0))
        fill.position = SIMD3<Float>(1.4, 1.0, 0.8)
        lights.append(fill)

        // Đèn viền đặt **phía sau** người, hơi cao hơn vai, chiếu về phía trước.
        let rim = DirectionalLight()
        rim.name = "light-rim"
        rim.light.intensity = baseRimIntensity
        rim.light.color = .white
        rim.orientation = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        rim.position = SIMD3<Float>(0.5, 1.7, -1.6)
        lights.append(rim)

        return lights
    }

    static func updateIntensity(in lights: [Entity], factor: Float) {
        for light in lights {
            guard var comp = light.components[DirectionalLightComponent.self] else { continue }
            switch light.name {
            case "light-key":
                comp.intensity = baseKeyIntensity * factor
            case "light-fill":
                comp.intensity = baseFillIntensity * factor
            case "light-rim":
                comp.intensity = baseRimIntensity * factor
            default:
                break
            }
            light.components.set(comp)
        }
    }
}

// MARK: - Dựng cảnh

/// Dựng cảnh 3D chỉ gồm người mẫu 3D ở tư thế đã chọn (không vẽ khối bàn ghế hộp gây che khuất).
@MainActor
enum GuideSceneBuilder {
    static func build(pose: ShootingPose, metrics: FigureMetrics) -> Entity {
        let root = Entity()
        root.name = "guide-root"

        if let rigged = FigureAssetLoader.load(pose: pose, metrics: metrics) {
            root.addChild(rigged)
        } else {
            root.addChild(FigureBuilder.makeFigure(pose: pose, metrics: metrics))
        }
        return root
    }

    /// Giải phóng đệ quy toàn bộ mesh, material, animation và cây thực thể con khỏi bộ nhớ GPU/RAM
    /// trước khi nạp mẫu 3D mới.
    static func releaseEntityHierarchy(_ entity: Entity?) {
        guard let entity else { return }
        for child in Array(entity.children) {
            releaseEntityHierarchy(child)
        }
        entity.stopAllAnimations()
        entity.components.remove(ModelComponent.self)
        entity.components.remove(DirectionalLightComponent.self)
        entity.removeFromParent()
    }
}
