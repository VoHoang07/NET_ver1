@preconcurrency import AVFoundation
import Combine
import CoreImage
import Photos
import SwiftUI
import UIKit

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    nonisolated(unsafe) let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "vn.net.camera.session")
    /// Queue phân tích khung hình — tách khỏi session queue để việc đo đạc
    /// không chặn việc cấu hình session.
    private let analysisQueue = DispatchQueue(label: "vn.net.camera.analysis", qos: .userInitiated)
    private nonisolated(unsafe) let photoOutput = AVCapturePhotoOutput()
    private nonisolated(unsafe) let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let frameAnalyzer = FrameAnalyzer()
    private let ciContext = CIContext()

    /// Số khung hình giữa hai lần phân tích. 10 fps đủ để phản hồi tức thì mà
    /// không làm nóng máy.
    nonisolated private static let analysisIntervalInFrames = 6
    /// Chỉ đọc/ghi trên `analysisQueue` nên không cần khóa main actor.
    private nonisolated(unsafe) var framesSinceLastAnalysis = 0

    private nonisolated(unsafe) var isConfigured = false
    private nonisolated(unsafe) var pendingMoods: [Int64: Mood] = [:]
    private nonisolated(unsafe) var captureDevice: AVCaptureDevice?
    private weak var previewLayerRef: AVCaptureVideoPreviewLayer?

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?

    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isPhotoLibraryAccessDenied = false
    @Published private(set) var setupError: String?
    @Published private(set) var lastCapture: CapturedPhoto?
    @Published private(set) var isCapturing = false
    @Published private(set) var isReady = false
    @Published private(set) var isFlashOn = false
    @Published private(set) var isFlashAvailable = true
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var position: AVCaptureDevice.Position = .back
    /// Cho biết `ARView` đang nắm quyền điều khiển camera qua `ARWorldTrackingConfiguration`.
    /// Không gắn `@Published` vì được cập nhật từ `UIViewRepresentable.makeUIView/updateUIView`.
    private(set) var isExternalARActive = false
    /// Cho biết ARKit đã nhận diện được mặt sàn thật và ghim cứng mẫu 3D xuống đất hay chưa.
    private(set) var isFloorLocked = false
    /// Yêu cầu đặt lại điểm neo sàn tại toạ độ màn hình khi người dùng chạm vào khung ngắm.
    @Published private(set) var floorAnchorTapPoint: CGPoint?
    @Published private(set) var floorAnchorTapID = UUID()

    private nonisolated(unsafe) var latestARPixelBuffer: CVPixelBuffer?

    /// Đo đạc gần nhất, đã quy về toạ độ khung hiển thị.
    @Published private(set) var latestAnalysis: FrameAnalyzer.Analysis?
    /// Kích thước khung hiển thị — cần cho `SafeArea` để quy đổi toạ độ.
    ///
    /// Main actor là nguồn sự thật, nhưng analyzer đọc từ `analysisQueue` nên
    /// giá trị cũng được đẩy sang `analysisConfiguration`.
    var viewportSize: CGSize = .zero {
        didSet {
            let size = viewportSize
            analysisConfiguration.update { $0.viewportSize = size }
        }
    }
    /// Chế độ chụp hiện tại — quyết định dùng khuôn nào và chấm tiêu chí nào.
    @Published var mode: CaptureMode = .solo {
        didSet {
            let newMode = mode
            analysisConfiguration.update { $0.mode = newMode }
        }
    }

    var isCameraAuthorized: Bool { authorization == .authorized }

    private nonisolated static func askForVideoAccess(_ onResult: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in onResult(granted) }
        }
    }

    // MARK: - Session lifecycle

    func requestAccessAndStart() {
        #if targetEnvironment(simulator)
        start()
        return
        #else
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            start()
        case .notDetermined:
            Self.askForVideoAccess { [weak self] granted in
                guard let self else { return }
                self.authorization = granted ? .authorized : .denied
                if granted { self.start() }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
        #endif
    }

    /// Cập nhật lại quyền truy cập và khôi phục phiên chạy khi ứng dụng quay về `.active`.
    func refreshAuthorizationAndResume() {
        let photoStatus = PhotoLibraryAuth.currentStatus
        if photoStatus == .authorized || photoStatus == .limited {
            isPhotoLibraryAccessDenied = false
        }
        #if targetEnvironment(simulator)
        start()
        #else
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .authorized && !isExternalARActive {
            start()
        }
        #endif
    }

    /// Tạm dừng phiên chạy Camera và giải phóng buffer tạm khi ứng dụng chuyển sang `.background`.
    func pauseForBackground() {
        latestARPixelBuffer = nil
        if isFlashOn {
            isFlashOn = false
            setHardwareTorch(enabled: false)
        }
        stop()
    }

    /// Chuyển quyền sử dụng camera giữa `AVCaptureSession` và `ARSession` (`ARWorldTrackingConfiguration`).
    ///
    /// Trên iOS, chỉ một session được phép mở phần cứng camera tại một thời điểm. Khi `ARView`
    /// bật chế độ AR thực (`.ar`) để dò mặt phẳng sàn và neo mẫu 3D, `AVCaptureSession` phải
    /// nhường quyền và nhận frame trực tiếp từ `ARSession`.
    func setExternalARActive(_ active: Bool) {
        guard isExternalARActive != active else { return }
        isExternalARActive = active
        isFloorLocked = false
        if active {
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isReady { self.isReady = true }
                if self.setupError != nil { self.setupError = nil }
            }
        } else {
            latestARPixelBuffer = nil
            Task { @MainActor [weak self] in
                guard let self, self.isCameraAuthorized else { return }
                self.start()
            }
        }
    }

    /// Cập nhật trạng thái khoá mặt sàn thực tế từ `ARSession`.
    func setFloorLocked(_ locked: Bool) {
        if isFloorLocked != locked {
            isFloorLocked = locked
        }
    }

    /// Nhận `CVPixelBuffer` trực tiếp từ `ARFrame.capturedImage` khi chạy `ARWorldTrackingConfiguration`.
    nonisolated func ingestARPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        latestARPixelBuffer = pixelBuffer
        framesSinceLastAnalysis += 1
        guard framesSinceLastAnalysis >= Self.analysisIntervalInFrames else { return }
        framesSinceLastAnalysis = 0

        analysisQueue.async { [weak self] in
            guard let self, let currentBuffer = self.latestARPixelBuffer else { return }
            let configuration = self.analysisConfiguration.current
            let viewport = configuration.viewportSize
            let safeArea: SafeArea? = viewport.width > 0 && viewport.height > 0
                ? SafeArea(viewSize: viewport, bufferSize: self.bufferSize(of: currentBuffer), fillsView: true)
                : nil

            let analysis = self.frameAnalyzer.analyze(
                pixelBuffer: currentBuffer,
                orientation: configuration.orientation,
                safeArea: safeArea,
                wantsBackgroundAnalysis: configuration.needsBackgroundAnalysis
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isReady { self.isReady = true }
                self.latestAnalysis = analysis
            }
        }
    }

    func requestFloorAnchor(at point: CGPoint) {
        floorAnchorTapPoint = point
        floorAnchorTapID = UUID()
    }

    func start() {
        #if targetEnvironment(simulator)
        authorization = .authorized
        isReady = true
        setupError = nil
        return
        #else
        guard !isExternalARActive else {
            isReady = true
            setupError = nil
            return
        }
        let desiredPosition = position
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession(position: desiredPosition)
            }
            guard self.isConfigured else { return }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let running = self.session.isRunning
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isReady = running
                if running { self.setupError = nil }
            }
        }
        #endif
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor [weak self] in self?.isReady = false }
        }
    }

    // MARK: - Controls

    func toggleFlash() {
        guard isFlashAvailable else {
            isFlashOn = false
            return
        }
        isFlashOn.toggle()
        if isExternalARActive {
            setHardwareTorch(enabled: isFlashOn)
        }
    }

    private func setHardwareTorch(enabled: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let targetMode: AVCaptureDevice.TorchMode = enabled ? .on : .off
            if device.isTorchModeSupported(targetMode) {
                device.torchMode = targetMode
            }
        } catch {
            // Không đổi được trạng thái đèn chiếu phụ thì bỏ qua an toàn.
        }
    }

    func toggleCamera() {
        if isFlashOn {
            setHardwareTorch(enabled: false)
        }
        let newPosition: AVCaptureDevice.Position = (position == .back) ? .front : .back
        position = newPosition
        if let candidate = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) {
            let hasFlash = candidate.hasFlash || candidate.hasTorch
            isFlashAvailable = hasFlash
            if !hasFlash { isFlashOn = false }
        }

        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            self.replaceInput(position: newPosition)
        }
    }

    func attachPreview(layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        previewLayerRef = layer
        updateRotationCoordinator()
    }

    func focus(atLayerPoint point: CGPoint) {
        if isExternalARActive {
            requestFloorAnchor(at: point)
            return
        }
        guard let layer = previewLayerRef else { return }
        focus(atDevicePoint: layer.captureDevicePointConverted(fromLayerPoint: point))
    }

    func capturePhoto(with mood: Mood) {
        if isExternalARActive {
            guard latestARPixelBuffer != nil else {
                reportSetupError("Camera AR đang khởi tạo. Hãy thử lại ngay.")
                return
            }
            isCapturing = true
            analysisQueue.async { [weak self] in
                guard let self, let currentBuffer = self.latestARPixelBuffer else {
                    Task { @MainActor [weak self] in self?.isCapturing = false }
                    return
                }
                let ciImage = CIImage(cvPixelBuffer: currentBuffer).oriented(.right)
                guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    Task { @MainActor [weak self] in self?.isCapturing = false }
                    return
                }
                let rawImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                let filteredImage = self.applyMoodFilter(to: rawImage, mood: mood)
                Task { @MainActor [weak self] in
                    self?.isCapturing = false
                    self?.lastCapture = CapturedPhoto(image: filteredImage)
                }
                self.saveToLibrary(filteredImage)
            }
            return
        }

        let flashOn = isFlashOn

        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, self.session.isRunning else {
                self?.reportSetupError("Camera chưa sẵn sàng. Hãy đợi một chút rồi thử lại.")
                return
            }

            let settings = AVCapturePhotoSettings()
            let flashMode: AVCaptureDevice.FlashMode = flashOn ? .on : .off
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization

            // Gắn mood vào chính request này để ảnh sau không bị đổi mood khi người dùng chụp tiếp.
            self.pendingMoods[settings.uniqueID] = mood
            Task { @MainActor in self.isCapturing = true }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Session configuration

    private nonisolated func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            reportSetupError("Thiết bị này không có camera phù hợp.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                reportSetupError("Không thể mở camera.")
                return
            }
            session.addInput(input)

            if !session.outputs.contains(photoOutput) {
                guard session.canAddOutput(photoOutput) else {
                    reportSetupError("Không thể khởi tạo bộ chụp ảnh.")
                    return
                }
                session.addOutput(photoOutput)
            }
            photoOutput.maxPhotoQualityPrioritization = .quality

            if !session.outputs.contains(videoOutput) {
                guard session.canAddOutput(videoOutput) else {
                    reportSetupError("Không thể khởi tạo phân tích khung hình.")
                    return
                }
                videoOutput.alwaysDiscardsLateVideoFrames = true
                // Khai báo rõ pixel format để analyzer luôn đọc được luma plane
                // ở byte đầu tiên của buffer.
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
                session.addOutput(videoOutput)
                configureFrameRate()
            }

            captureDevice = device
            isConfigured = true
            let hasFlash = device.hasFlash || device.hasTorch
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isFlashAvailable = hasFlash
                if !hasFlash { self.isFlashOn = false }
                self.updateRotationCoordinator()
            }
        } catch {
            reportSetupError(error.localizedDescription)
        }
    }

    private nonisolated func replaceInput(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach(session.removeInput)

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            reportSetupError("Không chuyển được sang camera mới.")
            return
        }

        session.addInput(input)
        captureDevice = device
        let hasFlash = device.hasFlash || device.hasTorch
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isFlashAvailable = hasFlash
            if !hasFlash { self.isFlashOn = false }
            self.updateRotationCoordinator()
        }
    }

// MARK: - Zoom

    /// Đặt mức zoom, kẹp trong khoảng camera cho phép.
    ///
    /// ## Vì sao bật chống rung
    ///
    /// Zoom xa thì mọi rung tay nhân lên theo. Ảnh chân dung mà mờ thì vô nghĩa —
    /// nét là điều kiện tiên quyết, không có gì bù được. Nên đánh đổi **nét bị trễ
    /// một chút** lấy ảnh không rung.
    ///
    /// - Parameters:
    ///   - factor: mức zoom mong muốn. Giá trị dưới 1 bị ép về 1.
    ///   - animated: xoay mượt hay nhảy thẳng. `false` khi app tự chọn zoom theo
    ///     tư thế — nhảy thẳng nhanh và không gây giật.
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }

            let clamped = max(factor, 1)
            let upper = min(device.activeFormat.videoMaxZoomFactor, 10)
            let target = min(clamped, upper)

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if animated {
                    device.ramp(toVideoZoomFactor: target, withRate: 4)
                } else {
                    device.videoZoomFactor = target
                }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }

                Task { @MainActor in self.zoomFactor = target }
            } catch {
                self.reportSetupError("Không zoom được: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated func focus(atDevicePoint point: CGPoint) {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
        } catch {
            reportSetupError("Không lấy nét được: \(error.localizedDescription)")
        }
    }

    private nonisolated func reportSetupError(_ message: String) {
        Task { @MainActor [weak self] in
            self?.setupError = message
            self?.isReady = false
        }
    }

    // MARK: - Frame rate

    /// Giới hạn fps của output phân tích.
    ///
    /// `AVCaptureVideoDataOutput` **không có** `activeVideoMinFrameDuration` như
    /// session — phải đặt trên `AVCaptureDevice`.
    nonisolated private func configureFrameRate() {
        guard let device = captureDevice else { return }

        let targetFPS: Int32 = 15
        let supportsTarget = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate >= Double(targetFPS)
        }
        guard supportsTarget else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: targetFPS)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: targetFPS)
        } catch {
            // Không giới hạn được vẫn chạy được, chỉ tốn nhiều năng lượng hơn.
        }
    }

    // MARK: - Frame analysis

    /// Cầu nối cho analyzer đọc cấu hình từ queue riêng.
    private let analysisConfiguration = AnalysisConfigurationStore()

    // MARK: - Rotation

    private func updateRotationCoordinator() {
        guard let device = captureDevice, let layer = previewLayerRef else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotationCoordinator = coordinator

        // KVO có thể gọi lại trên bất kỳ thread nào, nên phải nhảy về main actor
        // bằng `Task` thay vì `assumeIsolated` (sẽ crash nếu gọi ngoài main thread).
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPreviewRotation(self.rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 0)
            }
        }
        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyCaptureRotation(self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0)
            }
        }

        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayerRef?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        guard let connection = photoOutput.connection(with: .video),              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

// MARK: - Photo capture delegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let mood = pendingMoods.removeValue(forKey: photo.resolvedSettings.uniqueID) ?? .natural

        if let error {
            Task { @MainActor [weak self] in
                self?.isCapturing = false
                self?.setupError = "Không chụp được ảnh: \(error.localizedDescription)"
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            Task { @MainActor [weak self] in self?.isCapturing = false }
            return
        }

        let filteredImage = applyMoodFilter(to: rawImage, mood: mood)

        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.lastCapture = CapturedPhoto(image: filteredImage)
        }
        saveToLibrary(filteredImage)
    }

    nonisolated private func applyMoodFilter(to image: UIImage, mood: Mood) -> UIImage {
        guard mood != .natural, let input = CIImage(image: image) else { return image }

        var output = input
        switch mood {
        case .natural:
            break
        case .warm:
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                filter.setValue(CIVector(x: 5000, y: 0), forKey: "inputTargetNeutral")
                output = filter.outputImage ?? input
            }
        case .cool:
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: 5000, y: 0), forKey: "inputNeutral")
                filter.setValue(CIVector(x: 6800, y: 0), forKey: "inputTargetNeutral")
                output = filter.outputImage ?? input
            }
        case .film:
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(0.85, forKey: kCIInputSaturationKey)
                filter.setValue(1.1, forKey: kCIInputContrastKey)
                output = filter.outputImage ?? input
            }
        case .vintage:
            if let filter = CIFilter(name: "CISepiaTone") {
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(0.35, forKey: kCIInputIntensityKey)
                output = filter.outputImage ?? input
            }
        }

        // CIImage không mang orientation của UIImage, phải xoay thủ công rồi xuất ra với .up
        // để tránh việc orientation bị áp dụng hai lần (ảnh bị xoay sai).
        let oriented = output.oriented(CGImagePropertyOrientation(image.imageOrientation))
        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    nonisolated private func saveToLibrary(_ image: UIImage) {
        PhotoLibraryAuth.request { [weak self] status in
            guard status == .authorized || status == .limited else {
                if status == .denied || status == .restricted {
                    Task { @MainActor [weak self] in
                        self?.isPhotoLibraryAccessDenied = true
                    }
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.isPhotoLibraryAccessDenied = false
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { _, _ in }
        }
    }
}

// MARK: - SwiftUI Preview Layer

struct CameraPreview: UIViewRepresentable {
    let camera: CameraService

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.attachPreview(layer: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    /// Dùng `layerClass` để layer tự co giãn theo layout, không cần tính frame thủ công.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) chưa được hỗ trợ")
        }
    }
    }

    // MARK: - Frame analysis delegate

    extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        framesSinceLastAnalysis += 1
        guard framesSinceLastAnalysis >= Self.analysisIntervalInFrames else { return }
        framesSinceLastAnalysis = 0

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Đọc cấu hình qua store có khoá — hàm này chạy trên analysisQueue,
        // KHÔNG được chạm vào property của main actor.
        let configuration = analysisConfiguration.current

        // SafeArea chỉ hợp lệ khi đã biết kích thước khung hiển thị.
        let viewport = configuration.viewportSize
        let safeArea: SafeArea? = viewport.width > 0 && viewport.height > 0
            ? SafeArea(viewSize: viewport, bufferSize: bufferSize(of: pixelBuffer), fillsView: true)
            : nil

        let analysis = frameAnalyzer.analyze(
            pixelBuffer: pixelBuffer,
            orientation: configuration.orientation,
            safeArea: safeArea,
            wantsBackgroundAnalysis: configuration.needsBackgroundAnalysis
        )

        Task { @MainActor [weak self] in
            self?.latestAnalysis = analysis
        }
        }

        nonisolated private func bufferSize(of pixelBuffer: CVPixelBuffer) -> CGSize {
        CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        }
        }

extension CGImagePropertyOrientation {
    nonisolated init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
