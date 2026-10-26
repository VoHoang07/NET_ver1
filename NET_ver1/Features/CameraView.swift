import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraService()
    @State private var mood: Mood = .warm
    @State private var overlayVisible = true
    @State private var showGrid = true
    @State private var showGallery = false
    @State private var showAbout = false
    @State private var selectedRecipeIndex = 0
    @State private var viewportSize: CGSize = .zero
    @State private var isShutterPressed = false

    @Namespace private var poseNamespace

    /// Chiều cao người mẫu, đã nhập một lần. `nil` = chưa nhập, dùng giá trị trung bình.
    @State private var userHeight: UserHeight?
    /// Tư thế người dùng đã chọn — mặc định Đứng thẳng để thấy rõ toàn thân trên sàn thật.
    @State private var selectedPoseID: String = ShootingPose.standingStraight.id
    /// Sâu phòng đã đo, tính bằng mét. `nil` = chưa quét phòng.
    @State private var roomDepth: CGFloat?
    /// Tiến độ chờ chụp tự động.
    @State private var autoProgress: CGFloat = 0
    /// Bộ quyết định chụp tự động.
    @State private var autoDecider = AutoCaptureDecider()
    /// Có bật chụp tự động không.
    @State private var autoCaptureEnabled = true

    private var selectedPose: ShootingPose {
        ShootingPose.pose(id: selectedPoseID)
    }

    private var mode: CaptureMode { camera.mode }

    private var availableRecipes: [PhotoRecipe] {
        RecipeCatalog.recipes(for: mode)
    }

    private var template: PoseTemplate? {
        PoseTemplate.template(for: mode)
    }

    private var check: CaptureCheck {
        guard let analysis = camera.latestAnalysis else {
            return CaptureCheck(status: .notReady, results: [])
        }
        return CaptureCheckEvaluator.evaluate(analysis.measurements, mode: mode, template: template)
    }

    private var shutterIsActive: Bool {
        camera.isReady && !camera.isCapturing
    }

    var body: some View {
        ZStack {
            // 1. Khung ngắm toàn màn hình tràn viền (85% diện tích hoàn toàn thông thoáng)
            viewfinder
                .ignoresSafeArea()

            // Lớp phủ tối nhẹ ở sát mép trên và mép dưới để chữ trắng đọc rõ mà không làm đục khung hình
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.42), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.32), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 2. Giao diện tối giản chỉ gồm 1 thanh mỏng ở đỉnh và cụm điều khiển gọn ở đáy (tương thích cả iPhone và iPad 4:3)
            VStack(spacing: 0) {
                topBar
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Spacer()

                // Chỉ dẫn ngắn gọn 1 dòng duy nhất
                QualityCoachOverlay(check: check)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                // Dải chọn tư thế mỏng đặt ngay trên nút chụp (chuẩn Pro Camera)
                if mode.usesBodyTemplate {
                    poseStrip
                        .frame(maxWidth: 640)
                        .padding(.bottom, 14)
                }

                bottomControls
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)

            if !camera.isCameraAuthorized || camera.setupError != nil {
                blockingOverlay
            } else if camera.isPhotoLibraryAccessDenied {
                photoLibraryDeniedOverlay
            }
        }
        .sheet(isPresented: $showGallery) {
            GalleryView()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .task { camera.requestAccessAndStart() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                camera.refreshAuthorizationAndResume()
            case .background:
                autoDecider.reset()
                autoProgress = 0
                camera.pauseForBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: camera.latestAnalysis) { _, analysis in
            evaluateAutoCapture(analysis)
        }
        .onChange(of: selectedPoseID) { _, _ in
            autoDecider.reset()
            autoProgress = 0
        }
        .onChange(of: mode) { _, _ in
            selectedRecipeIndex = 0
        }
        .onChange(of: availableRecipes.count) { _, _ in
            selectedRecipeIndex = 0
        }
    }

    // MARK: - Auto Capture

    private func evaluateAutoCapture(_ analysis: FrameAnalyzer.Analysis?) {
        guard autoCaptureEnabled, !camera.isCapturing, let analysis else {
            autoProgress = 0
            return
        }
        guard let layout else {
            autoProgress = 0
            return
        }

        let current = PostureMatch.evaluate(
            pose: selectedPose,
            measurements: analysis.measurements,
            layout: layout
        )

        let eyesOpen = analysis.eyesOpen ?? true

        var headMoved = false
        if let head = analysis.measurements.bodyPose?.headCenter,
           let last = autoDecider.state.lastHeadX,
           abs(head.x - last) > 0.05 {
            headMoved = true
        }
        autoDecider.state.lastHeadX = analysis.measurements.bodyPose?.headCenter?.x

        let now = ContinuousClock().now
        switch autoDecider.evaluate(
            now: now,
            match: current,
            eyesOpen: eyesOpen,
            headMoved: headMoved
        ) {
        case .capture:
            triggerShutterHaptic()
            camera.capturePhoto(with: mood)
            autoDecider.reset()
            autoProgress = 1
        case .nearlyReady(let progress):
            autoProgress = progress
        case .waiting:
            autoProgress = 0
        }
    }

    // MARK: - Haptics

    private static let selectionFeedback = UISelectionFeedbackGenerator()
    private static let shutterFeedback = UIImpactFeedbackGenerator(style: .medium)

    private func triggerSelectionHaptic() {
        Self.selectionFeedback.selectionChanged()
    }

    private func triggerShutterHaptic() {
        Self.shutterFeedback.impactOccurred()
    }

    // MARK: - Top Bar (Chỉ 1 hàng duy nhất, sạch sẽ, không viền thừa iOS 26)

    private var topBar: some View {
        HStack(spacing: 10) {
            // Chạm để chuyển nhanh chế độ chụp (Chân dung / Cặp đôi / Nhóm / Vật thể)
            Button {
                triggerSelectionHaptic()
                let all = CaptureMode.allCases
                if let idx = all.firstIndex(of: camera.mode) {
                    camera.mode = all[(idx + 1) % all.count]
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("NÉT")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(camera.mode.title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.38), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Cụm công cụ nhanh (dùng .buttonStyle(.plain) để không bị iOS 26 chèn vòng tròn nâu)
            HStack(spacing: 2) {
                topToolButton(
                    icon: showGrid ? "squareshape.split.3x3" : "squareshape",
                    isActive: showGrid
                ) {
                    triggerSelectionHaptic()
                    withAnimation(.easeInOut(duration: 0.2)) { showGrid.toggle() }
                }

                topToolButton(
                    icon: overlayVisible ? "figure.stand" : "eye.slash",
                    isActive: overlayVisible
                ) {
                    triggerSelectionHaptic()
                    withAnimation(.easeInOut(duration: 0.2)) { overlayVisible.toggle() }
                }

                if camera.isFlashAvailable {
                    topToolButton(
                        icon: camera.isFlashOn ? "bolt.fill" : "bolt.slash",
                        isActive: camera.isFlashOn
                    ) {
                        triggerSelectionHaptic()
                        camera.toggleFlash()
                    }
                }

                topToolButton(
                    icon: "arrow.triangle.2.circlepath.camera",
                    isActive: false,
                    disabled: !camera.isReady
                ) {
                    triggerSelectionHaptic()
                    camera.toggleCamera()
                }

                topToolButton(
                    icon: "info.circle",
                    isActive: showAbout
                ) {
                    triggerSelectionHaptic()
                    showAbout = true
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.38), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
            }
        }
    }

    private func topToolButton(
        icon: String,
        isActive: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.62))
                .frame(width: 34, height: 30)
                .background {
                    if isActive {
                        Capsule().fill(Color.white.opacity(0.18))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Pose Dial (Đặt gọn phía trên nút Shutter như vòng xoay chế độ Camera Pro)

    private var poseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ShootingPose.all) { pose in
                        let isSelected = selectedPoseID == pose.id
                        Button {
                            guard selectedPoseID != pose.id else { return }
                            triggerSelectionHaptic()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedPoseID = pose.id
                                autoDecider.reset()
                                autoProgress = 0
                                proxy.scrollTo(pose.id, anchor: .center)
                            }
                        } label: {
                            Text(pose.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "activePoseDial", in: poseNamespace)
                                    } else {
                                        Capsule()
                                            .fill(Color.black.opacity(0.35))
                                    }
                                }
                                .overlay {
                                    if !isSelected {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                                    }
                                }
                        }
                        .id(pose.id)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(selectedPoseID, anchor: .center)
            }
        }
    }

    // MARK: - Full-bleed Viewfinder

    private var viewfinder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.05, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            CameraPreview(camera: camera)
                .ignoresSafeArea()

            templateOverlay
                .ignoresSafeArea()

            if showGrid {
                GridOverlay()
                    .ignoresSafeArea()
            }

            if !camera.isReady && camera.isCameraAuthorized {
                ProgressView()
                    .tint(.white)
            }
        }
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewportSize = newSize
            camera.viewportSize = newSize
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard camera.isReady else { return }
                triggerSelectionHaptic()
                camera.focus(atLayerPoint: value.location)
                let h = max(viewportSize.height, 844)
                if value.location.y > h * 0.16 && value.location.y < h * 0.77 {
                    camera.requestFloorAnchor(at: value.location)
                }
            }
        )
    }

    @ViewBuilder
    private var templateOverlay: some View {
        if mode.usesBodyTemplate, let metrics {
            TranslucentSceneView(
                pose: selectedPose,
                metrics: metrics,
                distance: figureDistance,
                zoomFactor: camera.zoomFactor,
                isAligned: match.isAligned,
                isTemplateVisible: overlayVisible,
                isAppActive: scenePhase == .active,
                cameraService: camera
            ) {
                autoProgressRing
            }
        } else if overlayVisible {
            ObjectTemplateOverlay(isSatisfied: check.status != .notReady)
        }
    }

    private var metrics: FigureMetrics? {
        selectedPose.metrics(userHeight: userHeight?.meters)
    }

    @ViewBuilder
    private var autoProgressRing: some View {
        if autoProgress > 0 {
            Circle()
                .trim(from: 0, to: autoProgress)
                .stroke(Color.netGreen, style: .init(lineWidth: 3, lineCap: .round))
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .stroke(Color.netGreen.opacity(0.25), lineWidth: 3)
                )
                .accessibilityLabel("Đang chờ chụp")
        }
    }

    private var figureDistance: CGFloat {
        roomDepth ?? selectedPose.cameraDistance
    }

    private var layout: SceneComposer.Layout? {
        SceneComposer.layout(
            pose: selectedPose,
            viewport: viewportSize,
            availableDepth: roomDepth,
            currentZoom: camera.zoomFactor
        )
    }

    private var match: PostureMatch {
        PostureMatch.evaluate(
            pose: selectedPose,
            measurements: camera.latestAnalysis?.measurements ?? CaptureMeasurements(),
            layout: layout
        )
    }

    // MARK: - Bottom Control Bar (Tinh gọn: Bộ sưu tập | Màu phim | Shutter | Đặt lại sàn)

    private var bottomControls: some View {
        HStack(alignment: .center) {
            // Cụm bên trái: Nút Bộ sưu tập & Nút chuyển Màu phim
            HStack(spacing: 10) {
                Button {
                    triggerSelectionHaptic()
                    showGallery = true
                } label: {
                    ZStack {
                        if let captured = camera.lastCapture {
                            Image(uiImage: captured.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.42))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)

                // Nút chuyển nhanh Màu phim (Mood) không dùng Menu hệ thống để tránh viền nâu iOS 26
                Button {
                    triggerSelectionHaptic()
                    let all = Mood.allCases
                    if let idx = all.firstIndex(of: mood) {
                        mood = all[(idx + 1) % all.count]
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.filters")
                            .font(.system(size: 13, weight: .medium))
                        Text(mood.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.42), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Nút Shutter đôi chuẩn Pro Camera
            Button {
                triggerShutterHaptic()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                    isShutterPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        isShutterPressed = false
                    }
                }
                camera.capturePhoto(with: mood)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.92), lineWidth: 3)
                        .frame(width: 74, height: 74)

                    Circle()
                        .fill(
                            camera.isCapturing
                                ? Color.netCoral
                                : (match.isAligned ? Color.netGreen : Color.white)
                        )
                        .frame(width: 60, height: 60)
                        .scaleEffect(isShutterPressed ? 0.88 : 1.0)
                }
            }
            .buttonStyle(.plain)
            .disabled(!shutterIsActive)

            // Cụm bên phải: Tự động quét & chọn góc đứng đẹp nhất trong khung hình
            HStack {
                Spacer()
                Button {
                    triggerSelectionHaptic()
                    if mode.usesBodyTemplate {
                        if let layout {
                            camera.setZoom(layout.suggestedZoom)
                        }
                        camera.requestFloorAnchor(at: .zero)
                    } else {
                        camera.setZoom(1.0)
                        let center = CGPoint(x: max(viewportSize.width, 390) * 0.5, y: max(viewportSize.height, 844) * 0.5)
                        camera.focus(atLayerPoint: center)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: match.isAligned ? "checkmark.circle.fill" : "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text(match.isAligned ? "Đã khớp" : "Góc đẹp")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(match.isAligned ? Color.netGreen : .white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.42), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(
                            match.isAligned ? Color.netGreen.opacity(0.55) : Color.white.opacity(0.18),
                            lineWidth: 0.7
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Blocking & Permission Denied Overlays (App Store Guideline 2.1 & 5.1.1)

    private var blockingOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(camera.setupError == nil ? .white : Color.netCoral)

            Text(camera.setupError.map { _ in "Camera đang bận" } ?? "NÉT cần quyền truy cập Camera")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(
                camera.setupError
                    ?? "Ứng dụng cần quyền truy cập Camera để hiển thị trực tiếp mô hình 3D tạo dáng trên khung ngắm, giúp bạn căn chỉnh góc chụp và bố cục hình ảnh."
            )
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 12) {
                Button("Mở Cài đặt") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.netCoral, in: Capsule())
                .foregroundStyle(.white)

                if camera.setupError != nil {
                    Button("Thử lại") {
                        camera.start()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                    }
                    .foregroundStyle(.white)
                } else if camera.authorization == .notDetermined {
                    Button("Cho phép") {
                        camera.requestAccessAndStart()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.netGreen, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(26)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        }
        .padding(28)
    }

    private var photoLibraryDeniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.netCoral)

            Text("Cần quyền truy cập Thư viện ảnh")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Ứng dụng cần quyền truy cập Thư viện ảnh để lưu lại bức ảnh bạn vừa chụp vào thiết bị.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 12) {
                Button("Mở Cài đặt") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.netCoral, in: Capsule())
                .foregroundStyle(.white)

                Button("Đóng") {
                    camera.isPhotoLibraryAccessDenied = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.45), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                }
                .foregroundStyle(.white)
            }
        }
        .padding(26)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        }
        .padding(28)
    }
}
