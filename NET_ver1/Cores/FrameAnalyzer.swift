import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision

/// Đo đạc khung hình từ `CVPixelBuffer`.
///
/// ## Ranh giới với domain
///
/// Lớp này chỉ **đo**, không **quyết định**. Kết quả trả về là
/// `CaptureMeasurements` — cấu trúc thuần, đưa sang `CaptureCheckEvaluator` để
/// chấm trạng thái. Nhờ vậy toàn bộ logic quyết định test được không cần camera.
///
/// ## Hiệu năng
///
/// Mọi Vision request được gộp vào **một** lần `perform` — cùng một lần decode
/// ảnh thay vì mỗi request một lần. Đây là khác biệt lớn nhất so với gọi tuần tự.
nonisolated final class FrameAnalyzer: @unchecked Sendable {
    nonisolated struct Analysis: Sendable, Equatable {
        var measurements = CaptureMeasurements()
        var bufferSize: CGSize = .zero
        var orientation: CGImagePropertyOrientation = .right

        /// Mắt đang mở không — điều kiện thứ ba cho chụp tự động.
        ///
        /// `nil` = không xác định (mặt quá nhỏ, hoặc quay nghiêng). Khi đó coi
        /// như mở, vì bỏ chụp vì "không biết" tệ hơn chụp rồi mới thấy hơi mờ.
        var eyesOpen: Bool?
    }

    /// Ngưỡng bão hoà — trên giá trị này pixel được coi là cháy sáng.
    nonisolated private static let clippedLumaThreshold: UInt8 = 245
    nonisolated private static let shadowLumaThreshold: UInt8 = 18

    /// Tái sử dụng các đối tượng `VNRequest` trên `analysisQueue` để tránh cấp phát lại mỗi khung hình.
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let landmarkRequest = VNDetectFaceLandmarksRequest()
    private let horizonRequest = VNDetectHorizonRequest()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    // MARK: - Phân tích

    /// - Parameters:
    ///   - pixelBuffer: buffer từ `AVCaptureVideoDataOutput`. Chỉ hợp lệ trong lời gọi.
    ///   - orientation: hướng của buffer so với màn hình.
    ///   - safeArea: dùng để quy đổi bbox Vision sang toạ độ khung hiển thị.
    ///   - wantsBackgroundAnalysis: có cần đo độ bận nền (tốn thêm 1 request).
    func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        safeArea: SafeArea?,
        wantsBackgroundAnalysis: Bool
    ) -> Analysis {
        var analysis = Analysis()
        analysis.bufferSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        analysis.orientation = orientation

        let luminance = analyzeLuminance(pixelBuffer)
        analysis.measurements.overexposedRatio = luminance.overexposedRatio
        analysis.measurements.underexposedRatio = luminance.underexposedRatio
        analysis.measurements.centerToEdgeLuminance = luminance.centerToEdgeRatio
        analysis.measurements.sharpness = sharpness(pixelBuffer)

        let vision = runVision(
            on: pixelBuffer,
            orientation: orientation,
            wantsSegmentation: wantsBackgroundAnalysis
        )

        analysis.measurements.hasPerson = !vision.faces.isEmpty
        analysis.measurements.detectedPersonCount = vision.faceCount
        analysis.eyesOpen = Self.eyesOpen(from: vision.faces)

        if let face = vision.faces.first {
            analysis.measurements.eyePoint = safeArea?.viewPoint(fromVisionPoint: face.eyeMidpoint)
            analysis.measurements.faceShadowRatio = faceShadowRatio(
                pixelBuffer, visionBox: face.boundingBox
            )
            analysis.measurements.subjectRect = safeArea?.viewRect(fromVisionRect: face.boundingBox)
        } else if let subjectBox = vision.subjectBox {
            analysis.measurements.hasSubject = true
            analysis.measurements.subjectRect = safeArea?.viewRect(fromVisionRect: subjectBox)
        }

        if let angle = vision.horizonAngle {
            analysis.measurements.horizonAngle = angle
        }

        // Tư thế đo được ở hệ Vision; quy đổi sang khung hiển thị để dùng chung
        // với `eyePoint` và `subjectRect`.
        if let pose = vision.bodyPose {
            analysis.measurements.bodyPose = Self.viewPose(pose, safeArea: safeArea)
        }

        if let mask = vision.subjectMask {
            analysis.measurements.backgroundClutter = backgroundClutter(mask)
        }

        return analysis
    }

    // MARK: - Vision

    nonisolated private struct DetectedFace {
        var boundingBox: CGRect
        var eyeMidpoint: CGPoint
        /// Chiều cao mí mắt chia cho chiều cao bbox mặt — dùng đoán mắt mở.
        var eyeOpenRatio: CGFloat?
    }

    nonisolated private struct VisionResult {
        var faces: [DetectedFace] = []
        var faceCount: Int = 0
        var subjectBox: CGRect?
        var bodyPose: BodyPose?
        /// `VNDetectHorizonResult.angle` là `CGFloat` (độ), dương = nghiêng sang phải.
        var horizonAngle: CGFloat?
        var subjectMask: CVPixelBuffer?
    }

    private func runVision(
        on pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        wantsSegmentation: Bool
    ) -> VisionResult {
        var result = VisionResult()

        // Đo tư thế: vai/hông/gối là thứ quyết định người mẫu có đang tạo dáng
        // đúng không. Không có nó thì app chỉ hướng dẫn được, không chấm được.
        var requests: [VNRequest] = [faceRequest, landmarkRequest, horizonRequest, poseRequest]
        if wantsSegmentation {
            requests.append(segmentationRequest)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try? handler.perform(requests)

        let observations: [VNFaceObservation] = faceRequest.results ?? []
        let landmarks: [VNFaceLandmarks2D] = (landmarkRequest.results ?? []).compactMap(\.landmarks)

        result.faceCount = observations.count
        result.faces = Self.pairFaces(observations: observations, landmarks: landmarks)

        // Lấy người có độ tin cậy cao nhất — khung hình có thể có nhiều người,
        // nhưng người dùng chỉ đang tạo dáng một người.
        let poseObservations = (poseRequest.results ?? [])
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
        if let best = poseObservations.first {
            result.bodyPose = Self.bodyPose(from: best)
        }

        if let horizonObservation = horizonRequest.results?.first {
            result.horizonAngle = horizonObservation.angle
        }

        if wantsSegmentation {
            let maskObservations: [VNPixelBufferObservation] = segmentationRequest.results ?? []
            result.subjectMask = maskObservations.first?.pixelBuffer
            // Bbox chủ thể suy ra từ chính mask, không cần request saliency riêng.
            if let mask = result.subjectMask, let box = boundingBox(of: mask) {
                result.subjectBox = box
            }
        }

        return result
        }

        /// Bbox bao trọn vùng có giá trị trong mask, quy về toạ độ chuẩn hoá 0...1
        /// theo hệ Vision (gốc đáy-trái).
        private func boundingBox(of mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let plane = base.assumingMemoryBound(to: UInt8.self)

        var minX = width, maxX = 0, minY = height, maxY = 0
        var found = false

        var y = 0
        while y < height {
            let row = y * bytesPerRow
            var x = 0
            while x < width {
                if Int(plane[row + x]) > 40 {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                x += 2
            }
            y += 2
        }

        guard found else { return nil }

        // Y của mask chạy từ trên xuống, Vision cần gốc đáy-trái.
        let top = CGFloat(minY) / CGFloat(height)
        let bottom = CGFloat(maxY + 1) / CGFloat(height)
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: 1 - bottom,
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: bottom - top
        )
        }

        private static func viewPose(_ pose: BodyPose, safeArea: SafeArea?) -> BodyPose {
        guard let safeArea else { return pose }

        func convert(_ point: CGPoint?) -> CGPoint? {
            point.map { safeArea.viewPoint(fromVisionPoint: $0) }
        }

        var joints = pose.joints
        joints.nose = convert(joints.nose)
        joints.neck = convert(joints.neck)
        joints.leftShoulder = convert(joints.leftShoulder)
        joints.rightShoulder = convert(joints.rightShoulder)
        joints.leftElbow = convert(joints.leftElbow)
        joints.rightElbow = convert(joints.rightElbow)
        joints.leftWrist = convert(joints.leftWrist)
        joints.rightWrist = convert(joints.rightWrist)
        joints.leftHip = convert(joints.leftHip)
        joints.rightHip = convert(joints.rightHip)
        joints.leftKnee = convert(joints.leftKnee)
        joints.rightKnee = convert(joints.rightKnee)
        joints.leftAnkle = convert(joints.leftAnkle)
        joints.rightAnkle = convert(joints.rightAnkle)

        return BodyPose(joints: joints)
        }

        /// Chuyển quan sát tư thế của Vision sang `BodyPose`.
        ///
        /// Giữ nguyên toạ độ chuẩn hoá của Vision (gốc đáy-trái) — `SafeArea` lo
        /// việc quy đổi sang khung hiển thị.
        private static func bodyPose(from observation: VNHumanBodyPoseObservation) -> BodyPose? {
        let points = try? observation.recognizedPoints(.all)

        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = points?[joint], p.confidence > 0.2 else { return nil }
            return p.location
        }

        var joints = BodyPose.Joints()
        joints.nose = point(.nose)
        joints.neck = point(.neck)
        joints.leftShoulder = point(.leftShoulder)
        joints.rightShoulder = point(.rightShoulder)
        joints.leftElbow = point(.leftElbow)
        joints.rightElbow = point(.rightElbow)
        joints.leftWrist = point(.leftWrist)
        joints.rightWrist = point(.rightWrist)
        joints.leftHip = point(.leftHip)
        joints.rightHip = point(.rightHip)
        joints.leftKnee = point(.leftKnee)
        joints.rightKnee = point(.rightKnee)
        joints.leftAnkle = point(.leftAnkle)
        joints.rightAnkle = point(.rightAnkle)

        let pose = BodyPose(joints: joints)
        return pose.isUsable ? pose : nil
        }

        /// Ghép quan sát mặt với bộ mốc tương ứng.
        ///
        /// `VNFaceLandmarks2D` **không có** `boundingBox` — bbox thuộc về
        /// `VNFaceObservation`, nên phải ghép theo chỉ số.
        private static func pairFaces(
        observations: [VNFaceObservation],
        landmarks: [VNFaceLandmarks2D]
        ) -> [DetectedFace] {
        var faces: [DetectedFace] = []
        faces.reserveCapacity(observations.count)

        for (index, observation) in observations.enumerated() {
            let box = observation.boundingBox
            guard index < landmarks.count else {
                faces.append(DetectedFace(
                    boundingBox: box, eyeMidpoint: box.center, eyeOpenRatio: nil
                ))
                continue
            }
            let faceLandmarks = landmarks[index]
            let midpoint = eyeMidpoint(faceLandmarks, faceBox: box) ?? box.center
            faces.append(DetectedFace(
                boundingBox: box,
                eyeMidpoint: midpoint,
                eyeOpenRatio: eyeOpenRatio(faceLandmarks, faceBox: box)
            ))
        }

        return faces
        }

/// Chiều cao mí mắt so với chiều cao bbox mặt.
        ///
        /// Lấy mí mắt trên và dưới của **một** mắt rồi chia cho chiều cao mặt.
        /// Dùng một mắt vì hai mắt có thể lệch và Vision hay thiếu một bên.
        private static func eyeOpenRatio(
            _ landmarks: VNFaceLandmarks2D,
            faceBox: CGRect
        ) -> CGFloat? {
            guard faceBox.height > 0 else { return nil }

            let eye = landmarks.leftEye ?? landmarks.rightEye
            guard let points = eye?.normalizedPoints, points.count >= 8 else { return nil }

            // Vision đo từ đáy lên, nên mí dưới có y nhỏ hơn mí trên.
            let ys = points.map(\.y)
            guard let lower = ys.min(), let upper = ys.max(), upper > lower else { return nil }

            return (upper - lower) / faceBox.height
        }

        /// Mắt đang mở không.
        ///
        /// - Important: đây là **ước lượng**, không phải đo chắc. Ngưỡng rộng cố ý,
        ///   vì bấm chụp nhầm lúc người mẫu chớp mắt thì mất lòng tin nhiều hơn là
        ///   bỏ lỡ một khoảnh khắc tốt.
        ///
        /// - Returns: `nil` khi không đo được — coi như mở, vì "không biết" thì đừng
        ///   ngăn chụp.
        private static func eyesOpen(from faces: [DetectedFace]) -> Bool? {
            guard let ratio = faces.first?.eyeOpenRatio else { return nil }
            return ratio > 0.035
        }

        /// Điểm giữa hai mắt, quy về toạ độ chuẩn hoá của **ảnh** (hệ Vision).
        private static func eyeMidpoint(_ landmarks: VNFaceLandmarks2D, faceBox: CGRect) -> CGPoint? {
        guard let left = landmarks.leftEye?.normalizedPoints,
              let right = landmarks.rightEye?.normalizedPoints else { return nil }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var total = 0

        for point in left {
            sumX += point.x
            sumY += point.y
            total += 1
        }
        for point in right {
            sumX += point.x
            sumY += point.y
            total += 1
        }

        guard total > 0 else { return nil }
        let centroid = CGPoint(x: sumX / CGFloat(total), y: sumY / CGFloat(total))

        // normalizedPoints nằm trong bbox mặt với gốc tại **trên-trái** của bbox,
        // còn bbox của Vision dùng gốc đáy-trái — nên phải quy đổi qua lại.
        let xInBox = faceBox.minX + centroid.x * faceBox.width
        let yFromTopOfBox = faceBox.maxY - centroid.y * faceBox.height
        return CGPoint(x: xInBox, y: yFromTopOfBox)
        }

    // MARK: - Pixel statistics

    /// Kết quả thống kê độ sáng.
    nonisolated struct LuminanceStats: Sendable {
        var overexposedRatio: CGFloat = 0
        var underexposedRatio: CGFloat = 0
        var centerToEdgeRatio: CGFloat = 1
    }

    private func analyzeLuminance(_ pixelBuffer: CVPixelBuffer) -> LuminanceStats {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return LuminanceStats()
        }

        let luma = base.assumingMemoryBound(to: UInt8.self)
        let centerMinX = width / 4, centerMaxX = width * 3 / 4
        let centerMinY = height / 4, centerMaxY = height * 3 / 4

        var clipped = 0, crushed = 0, sampled = 0
        var centerSum = 0, centerCount = 0
        var totalSum = 0

        // Bước 4 px là đủ để chấm điểm và giảm ~16 lần khối lượng tính.
        let step = 4
        var y = 0
        while y < height {
            let row = y * bytesPerRow
            var x = 0
            while x < width {
                let value = luma[row + x]
                sampled += 1
                totalSum += Int(value)

                if value >= Self.clippedLumaThreshold { clipped += 1 }
                if value <= Self.shadowLumaThreshold { crushed += 1 }

                if x >= centerMinX, x < centerMaxX, y >= centerMinY, y < centerMaxY {
                    centerSum += Int(value)
                    centerCount += 1
                }
                x += step
            }
            y += step
        }

        guard sampled > 0, centerCount > 0 else { return LuminanceStats() }

        let centerAverage = Double(centerSum) / Double(centerCount)
        let totalAverage = Double(totalSum) / Double(sampled)

        return LuminanceStats(
            overexposedRatio: CGFloat(clipped) / CGFloat(sampled),
            underexposedRatio: CGFloat(crushed) / CGFloat(sampled),
            centerToEdgeRatio: CGFloat(centerAverage / max(totalAverage, 1))
        )
    }

    /// Độ nét ước lượng bằng tổng gradient trên plane Y.
    private func sharpness(_ pixelBuffer: CVPixelBuffer) -> CGFloat {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard width > 8, height > 8, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let luma = base.assumingMemoryBound(to: UInt8.self)

        var total = 0.0
        var count = 0
        let step = 4

        var y = step
        while y < height - step {
            let row = y * bytesPerRow
            let rowDown = (y + step) * bytesPerRow

            var x = step
            while x < width - step {
                let center = Int(luma[row + x])
                let horizontal = abs(center - Int(luma[row + x + step]))
                let vertical = abs(center - Int(luma[rowDown + x]))
                total += Double(horizontal + vertical)
                count += 1
                x += step
            }
            y += step
        }

        guard count > 0 else { return 0 }
        return CGFloat(total / Double(count))
    }

    /// So sánh độ sáng trung tâm khuôn mặt với vành quanh nó.
    ///
    /// Trung tâm tối hơn vành nghĩa là **có bóng đổ** — lỗi phổ biến nhất trong
    /// ảnh chân dung, và là thứ người không có mắt nhiếp ảnh thường không nhận ra.
    private func faceShadowRatio(_ pixelBuffer: CVPixelBuffer, visionBox: CGRect) -> CGFloat {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 1 }
        let luma = base.assumingMemoryBound(to: UInt8.self)

        // Vision dùng gốc đáy-trải; plane Y bắt đầu từ hàng trên cùng.
        func toBufferPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * CGFloat(width), y: (1 - point.y) * CGFloat(height))
        }

        // Lấy 60% trung tâm bbox (trán + cằm), bỏ viền tóc và cằm.
        let innerVisionBox = CGRect(
            x: visionBox.minX + visionBox.width * 0.2,
            y: visionBox.minY + visionBox.height * 0.2,
            width: visionBox.width * 0.6,
            height: visionBox.height * 0.6
        )
        let ringVisionBox = CGRect(
            x: innerVisionBox.minX - visionBox.width * 0.4,
            y: innerVisionBox.minY - visionBox.height * 0.4,
            width: innerVisionBox.width + visionBox.width * 0.8,
            height: innerVisionBox.height + visionBox.height * 0.8
        )

        let center = meanLuma(luma, bytesPerRow: bytesPerRow, region: innerVisionBox, toBufferPoint: toBufferPoint)
        let ring = meanLuma(luma, bytesPerRow: bytesPerRow, region: ringVisionBox, toBufferPoint: toBufferPoint)

        guard let center, let ring, ring > 1 else { return 1 }
        return center / ring
    }

    private func meanLuma(
        _ luma: UnsafePointer<UInt8>,
        bytesPerRow: Int,
        region: CGRect,
        toBufferPoint: (CGPoint) -> CGPoint
    ) -> CGFloat? {
        let corners = [
            toBufferPoint(CGPoint(x: region.minX, y: region.minY)),
            toBufferPoint(CGPoint(x: region.maxX, y: region.minY)),
            toBufferPoint(CGPoint(x: region.minX, y: region.maxY)),
            toBufferPoint(CGPoint(x: region.maxX, y: region.maxY))
        ]
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? 0

        var sum = 0
        var count = 0
        var y = Int(minY)
        while y < Int(maxY) {
            let row = y * bytesPerRow
            var x = Int(minX)
            while x < Int(maxX) {
                sum += Int(luma[row + x])
                count += 1
                x += 4
            }
            y += 4
        }

        guard count > 0 else { return nil }
        return CGFloat(sum) / CGFloat(count)
    }

    /// Độ bận của nền: biến thiên cục bộ **ngoài** vùng người.
    private func backgroundClutter(_ mask: CVPixelBuffer) -> CGFloat {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let plane = base.assumingMemoryBound(to: UInt8.self)

        var edges = 0
        var backgroundSamples = 0

        var y = 2
        while y < height - 2 {
            let row = y * bytesPerRow
            var x = 2
            while x < width - 2 {
                let value = Int(plane[row + x])
                // Trên ngưỡng này thuộc người -> bỏ qua.
                if value > 40 {
                    x += 2
                    continue
                }
                backgroundSamples += 1
                let right = Int(plane[row + x + 2])
                let down = Int(plane[(y + 2) * bytesPerRow + x])
                if abs(value - right) > 40 || abs(value - down) > 40 {
                    edges += 1
                }
                x += 2
            }
            y += 2
        }

        guard backgroundSamples > 0 else { return 0 }
        return CGFloat(edges) / CGFloat(backgroundSamples)
    }
}

private extension CGRect {
    nonisolated var center: CGPoint { CGPoint(x: midX, y: midY) }
}
