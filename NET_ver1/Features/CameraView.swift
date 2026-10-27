import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    private enum ActiveDrawer: Equatable {
        case moodPalette
        case smartAssist
        case modeSelector
        case poseInspector(ShootingPose)
    }

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
    @State private var activeDrawer: ActiveDrawer?
    @State private var tapReticlePoint: CGPoint?
    @State private var tapReticleID = UUID()
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var isZoomWheelExpanded = false
    @State private var zoomDragStartFactor: CGFloat?
    @State private var lastZoomHapticStep: Int = 10
    @State private var zoomWheelDismissID = UUID()
    @State private var isMoodLongPressing = false
    @State private var isSmartSpotLongPressing = false
    @State private var isModeLongPressing = false

    /// Màu vàng chuẩn của vòng Zoom trên ứng dụng Camera iPhone (`#FFD60A`).
    private static let cameraYellow = Color(red: 1.0, green: 0.84, blue: 0.04)

    @Namespace private var poseNamespace

    /// Chiều cao người mẫu, đã nhập một lần. `nil` = chưa nhập, dùng giá trị trung bình.
    @State private var userHeight: UserHeight? = UserSettingsStore.loadHeight()
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

    private var currentHeightMeters: CGFloat {
        userHeight?.meters ?? UserHeight.defaultMeters
    }

    private var currentHeightCm: Int {
        Int((currentHeightMeters * 100).rounded())
    }

    private var mode: CaptureMode { camera.mode }

    private var availableRecipes: [PhotoRecipe] {
        RecipeCatalog.recipes(for: mode)
    }

    private var currentRecipe: PhotoRecipe {
        availableRecipes[safe: selectedRecipeIndex] ?? RecipeCatalog.defaultRecipe
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
                    colors: [.clear, .black.opacity(0.32), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 235)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 2. Giao diện Pro Camera (Leica LUX / Halide / SOVS): gọn gàng, hỗ trợ Chạm nhanh & Giữ im mở khay tuỳ chọn
            VStack(spacing: 0) {
                topBar
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                if activeDrawer == .modeSelector {
                    modeSelectorDrawer
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                Spacer()

                // Khay tuỳ chọn nổi theo ngữ cảnh (hiện khi Giữ im vào Tone màu, Góc đẹp, hoặc Tư thế)
                if let drawer = activeDrawer, drawer != .modeSelector {
                    contextualBottomDrawer(drawer)
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.94, anchor: .bottom)).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                // Chỉ dẫn AI 1 dòng gọn gàng phía trên cụm nút Zoom (ẩn tạm khi đang mở vòm xoay Zoom bán nguyệt)
                if !isZoomWheelExpanded {
                    QualityCoachOverlay(check: check)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                // Cụm điều khiển Zoom chuẩn Camera iPhone:
                // - Mặc định: 4 nút tròn (0.5 · 1x · 2 · 3)
                // - Khi giữ im / vuốt: bung khung nửa hình tròn (vòm bán nguyệt) ngay trên nút chụp ảnh y hệt Camera iPhone
                focalLengthDial
                    .padding(.bottom, isZoomWheelExpanded ? 2 : 10)

                // Dải chọn tư thế mỏng đặt ngay trên nút chụp (ẩn tạm khi đang xoay vòm Zoom bán nguyệt để vòm nằm sát nút chụp như Camera iPhone)
                if mode.usesBodyTemplate && !isZoomWheelExpanded {
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
        .task {
            camera.requestAccessAndStart()
            // Khởi tạo sẵn kết nối Haptics và nạp dần 6 tư thế USDZ ở nhịp nghỉ để lần bấm đầu tiên không bao giờ bị khựng
            try? await Task.sleep(for: .milliseconds(120))
            Self.selectionFeedback.prepare()
            Self.shutterFeedback.prepare()
            await FigureAssetLoader.warmUpPosesGradually()
        }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                camera.refreshAuthorizationAndResume()
            case .background:
                autoDecider.reset()
                autoProgress = 0
                activeDrawer = nil
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

    // MARK: - Top Bar (Chỉ 1 hàng duy nhất, hỗ trợ Chạm & Giữ im chuẩn Pro Camera)

    private var topBar: some View {
        HStack(spacing: 10) {
            // Chạm hoặc Giữ im để mở bảng chọn 4 Chế độ chụp & Công thức góc máy
            HStack(spacing: 6) {
                Image(systemName: camera.mode.iconName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.netGreen)
                Text("NÉT")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                Text("·")
                    .foregroundStyle(.white.opacity(0.4))
                Text(camera.mode.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: activeDrawer == .modeSelector ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                activeDrawer == .modeSelector ? Color.white.opacity(0.18) : Color.black.opacity(0.42),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    activeDrawer == .modeSelector ? Color.white.opacity(0.42) : Color.white.opacity(0.16),
                    lineWidth: 0.7
                )
            }
            .scaleEffect(isModeLongPressing ? 0.94 : 1.0)
            .contentShape(Capsule())
            .onTapGesture {
                triggerSelectionHaptic()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    activeDrawer = (activeDrawer == .modeSelector) ? nil : .modeSelector
                }
            }
            .onLongPressGesture(minimumDuration: 0.20, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isModeLongPressing = pressing
                }
            }) {
                triggerShutterHaptic()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    activeDrawer = .modeSelector
                }
            }

            Spacer()

            // Cụm công cụ nhanh (Chạm để bật/tắt, Giữ im nút 3D để chỉnh chiều cao mẫu & Auto-Shutter)
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
                    isActive: overlayVisible || activeDrawer == .smartAssist,
                    onLongPress: {
                        triggerShutterHaptic()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            activeDrawer = (activeDrawer == .smartAssist) ? nil : .smartAssist
                        }
                    }
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
            .background(Color.black.opacity(0.42), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
            }
        }
    }

    private func topToolButton(
        icon: String,
        isActive: Bool,
        disabled: Bool = false,
        onLongPress: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(
                disabled
                    ? Color.white.opacity(0.28)
                    : (isActive ? Color.white : Color.white.opacity(0.65))
            )
            .frame(width: 34, height: 30)
            .background {
                if isActive {
                    Capsule().fill(Color.white.opacity(0.18))
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                guard !disabled else { return }
                action()
            }
            .onLongPressGesture(minimumDuration: 0.24) {
                guard !disabled, let onLongPress else { return }
                onLongPress()
            }
    }

    // MARK: - iPhone Camera Semi-Circular Zoom Dial (Nút tròn 0.5 · 1x · 2 · 3 + Giữ im hiện khung nửa tròn xoay Zoom chuẩn iOS Camera)

    private struct LensPreset: Identifiable {
        let id: String
        let shortLabel: String
        let factor: CGFloat
        let activeRange: ClosedRange<CGFloat>
    }

    private struct ArcMajorStop: Identifiable {
        let id: String
        let factor: CGFloat
        let label: String
        let mmText: String?
    }

    private static let iPhoneLensPresets: [LensPreset] = [
        LensPreset(id: "0.5x", shortLabel: "0.5", factor: 0.5, activeRange: 0.49...0.89),
        LensPreset(id: "1x", shortLabel: "1", factor: 1.0, activeRange: 0.90...1.79),
        LensPreset(id: "2x", shortLabel: "2", factor: 2.0, activeRange: 1.80...2.69),
        LensPreset(id: "3x", shortLabel: "3", factor: 3.0, activeRange: 2.70...10.01)
    ]

    private static let iPhoneArcMajorStops: [ArcMajorStop] = [
        ArcMajorStop(id: "0.5", factor: 0.5, label: "0.5", mmText: "13MM"),
        ArcMajorStop(id: "1", factor: 1.0, label: "1", mmText: "26MM"),
        ArcMajorStop(id: "2", factor: 2.0, label: "2", mmText: "52MM"),
        ArcMajorStop(id: "3", factor: 3.0, label: "3", mmText: "77MM"),
        ArcMajorStop(id: "5", factor: 5.0, label: "5", mmText: "130MM"),
        ArcMajorStop(id: "10", factor: 10.0, label: "10", mmText: nil)
    ]

    /// Danh sách toàn bộ các vạch chia (cả chính lẫn phụ) trên vòng cung bán nguyệt `0.5x ... 10.0x`.
    private static let iPhoneArcTickFactors: [(factor: CGFloat, isMajor: Bool)] = {
        var list: [(CGFloat, Bool)] = []
        // 0.5 -> 1.0: mỗi vạch 0.1
        for i in 5...9 {
            let z = CGFloat(i) / 10.0
            list.append((z, i == 5))
        }
        // 1.0 -> 3.0: mỗi vạch 0.1
        for i in 10...30 {
            let z = CGFloat(i) / 10.0
            let isMajor = (i == 10 || i == 20 || i == 30)
            list.append((z, isMajor))
        }
        // 3.0 -> 5.0: 10 khoảng chia logarit
        let log3 = log2(3.0)
        let log5 = log2(5.0)
        for step in 1...10 {
            let t = CGFloat(step) / 10.0
            let z = pow(2.0, log3 + (log5 - log3) * t)
            list.append((z, step == 10))
        }
        // 5.0 -> 10.0: 14 khoảng chia logarit
        let log10 = log2(10.0)
        for step in 1...14 {
            let t = CGFloat(step) / 14.0
            let z = pow(2.0, log5 + (log10 - log5) * t)
            list.append((z, step == 14))
        }
        return list
    }()

    /// Góc mở (độ) cho mỗi lần nhân đôi tiêu cự (`1 octave = 23.5°`, khớp chính xác tỷ lệ vòm Camera iPhone).
    private static let degreesPerOctave: CGFloat = 23.5

    private func formattedZoomText(_ factor: CGFloat, includeX: Bool) -> String {
        let roundedTenth = (factor * 10).rounded() / 10
        let base: String
        if roundedTenth >= 0.96 && abs(roundedTenth - roundedTenth.rounded()) < 0.04 {
            base = "\(Int(roundedTenth.rounded()))"
        } else {
            base = String(format: "%.1f", roundedTenth)
        }
        return includeX ? "\(base)x" : base
    }

    private func equivalentFocalLengthMM(_ factor: CGFloat) -> Int {
        Int((26.0 * factor).rounded())
    }

    private func applyInteractiveZoom(_ target: CGFloat, animated: Bool) {
        let clamped = min(max(target, CameraService.minZoomFactor), CameraService.maxZoomFactor)
        let quantizedTenth = (clamped * 10).rounded() / 10
        let newStep = Int((quantizedTenth * 10).rounded())
        if newStep != lastZoomHapticStep {
            lastZoomHapticStep = newStep
            if newStep == 5 || newStep == 10 || newStep == 20 || newStep == 30 || newStep == 50 || newStep == 100 {
                Self.shutterFeedback.impactOccurred(intensity: 0.7)
            } else {
                triggerSelectionHaptic()
            }
        }
        pinchBaseZoom = clamped
        camera.setZoom(clamped, animated: animated)
    }

    private func openArcZoomWheel() {
        guard !isZoomWheelExpanded else { return }
        lastZoomHapticStep = Int((camera.zoomFactor * 10).rounded())
        Self.shutterFeedback.impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isZoomWheelExpanded = true
        }
    }

    private func scheduleZoomWheelAutoCollapse(after delay: TimeInterval = 1.6) {
        let token = UUID()
        zoomWheelDismissID = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if zoomWheelDismissID == token && zoomDragStartFactor == nil {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isZoomWheelExpanded = false
                }
            }
        }
    }

    private var focalLengthDial: some View {
        ZStack(alignment: .bottom) {
            if isZoomWheelExpanded {
                iPhoneArcZoomWheel
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.90, anchor: .bottom).combined(with: .opacity)
                    ))
            } else {
                iPhoneCompactLensBar
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Thanh nút tròn ống kính thu gọn (`0.5`, `1x`, `2`, `3`):
    /// - Chạm nhanh: chuyển tới tiêu cự đó (chạm lại nút đang chọn sẽ bung vòm xoay nửa tròn).
    /// - Giữ im (`>= 0.16s`) hoặc giữ kéo ngang: bung ngay **Khung nửa hình tròn xoay Zoom** và xoay liên tục theo ngón tay.
    private var iPhoneCompactLensBar: some View {
        HStack(spacing: 6) {
            ForEach(Self.iPhoneLensPresets) { preset in
                let isSelected = preset.activeRange.contains(camera.zoomFactor)
                let labelText = isSelected
                    ? formattedZoomText(camera.zoomFactor, includeX: true)
                    : preset.shortLabel

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.82) : Color.black.opacity(0.48))
                        .frame(width: isSelected ? 36 : 29, height: isSelected ? 36 : 29)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isSelected ? Self.cameraYellow.opacity(0.45) : Color.white.opacity(0.14),
                                    lineWidth: isSelected ? 1.0 : 0.6
                                )
                        }

                    Text(labelText)
                        .font(.system(size: isSelected ? 12 : 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Self.cameraYellow : .white.opacity(0.92))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .frame(width: isSelected ? 32 : 25)
                }
                .contentShape(Circle())
                .onTapGesture {
                    if isSelected && abs(camera.zoomFactor - preset.factor) < 0.05 {
                        openArcZoomWheel()
                        scheduleZoomWheelAutoCollapse(after: 2.0)
                    } else {
                        lastZoomHapticStep = Int((preset.factor * 10).rounded())
                        Self.shutterFeedback.impactOccurred(intensity: 0.65)
                        pinchBaseZoom = preset.factor
                        camera.setZoom(preset.factor, animated: true)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.16) {
                    openArcZoomWheel()
                    scheduleZoomWheelAutoCollapse(after: 2.2)
                }
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isSelected)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.7)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if zoomDragStartFactor == nil {
                        zoomDragStartFactor = camera.zoomFactor
                        openArcZoomWheel()
                    }
                    let base = zoomDragStartFactor ?? camera.zoomFactor
                    let logBase = log2(max(base, CameraService.minZoomFactor))
                    // Kéo sang trái (xoay vòm sang trái) kéo các số lớn (2, 3, 10) về kim chỉ giữa; kéo sang phải giảm về 0.5
                    let deltaOctaves = -value.translation.width / 82.0
                    let rawTarget = pow(2.0, logBase + deltaOctaves)
                    applyInteractiveZoom(rawTarget, animated: false)
                }
                .onEnded { _ in
                    zoomDragStartFactor = nil
                    scheduleZoomWheelAutoCollapse(after: 1.6)
                }
        )
    }

    /// Khung nửa hình tròn (vòm bán nguyệt) xoay tiêu cự chuẩn Camera iPhone (`0.5` / `13MM` · `1` / `26MM` · `2` / `52MM` · `3` / `77MM` · `10`).
    private var iPhoneArcZoomWheel: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = max(w * 0.67, 256.0)
            let center = CGPoint(x: w * 0.5, y: radius + 4.0)
            let currentZoom = max(camera.zoomFactor, CameraService.minZoomFactor)
            let currentLog = log2(currentZoom)

            ZStack {
                // 1. Nền vòm nửa hình tròn tối bán trong suốt + các vạch chia hướng tâm + kim chỉ tam giác vàng ở đỉnh 12h
                Canvas { context, _ in
                    let circleRect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let domePath = Path(ellipseIn: circleRect)

                    // Tô nền vòm bán nguyệt tối mờ giống hệt Camera iPhone
                    context.fill(
                        domePath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: Color.black.opacity(0.56), location: 0.0),
                                .init(color: Color.black.opacity(0.42), location: 0.45),
                                .init(color: Color.black.opacity(0.18), location: 1.0)
                            ]),
                            startPoint: CGPoint(x: center.x, y: center.y - radius),
                            endPoint: CGPoint(x: center.x, y: h)
                        )
                    )

                    // Viền cung tròn mảnh ở mép trên vòm
                    context.stroke(
                        domePath,
                        with: .color(Color.white.opacity(0.14)),
                        lineWidth: 0.8
                    )

                    // Vẽ các vạch chia hướng tâm (radial ticks) dọc theo cung tròn
                    for tick in Self.iPhoneArcTickFactors {
                        let angleDeg = (log2(tick.factor) - currentLog) * Self.degreesPerOctave
                        guard abs(angleDeg) <= 62.0 else { continue }
                        // Bỏ qua vạch nằm đè trực tiếp lên kim chỉ màu vàng ở đúng 0°
                        if abs(angleDeg) < 0.85 { continue }

                        let rad = angleDeg * .pi / 180.0
                        let sinA = sin(rad)
                        let cosA = cos(rad)

                        let edgeFade = max(0.0, min(1.0, (62.0 - abs(angleDeg)) / 14.0))
                        let rOuter = radius - 2.0
                        let tickLen: CGFloat = tick.isMajor ? 18.0 : 13.0
                        let rInner = rOuter - tickLen

                        let p1 = CGPoint(x: center.x + rOuter * sinA, y: center.y - rOuter * cosA)
                        let p2 = CGPoint(x: center.x + rInner * sinA, y: center.y - rInner * cosA)

                        var line = Path()
                        line.move(to: p1)
                        line.addLine(to: p2)

                        let alpha = (tick.isMajor ? 0.95 : 0.36) * edgeFade
                        context.stroke(
                            line,
                            with: .color(Color.white.opacity(alpha)),
                            style: StrokeStyle(lineWidth: tick.isMajor ? 1.8 : 1.0, lineCap: .round)
                        )
                    }

                    // Kim chỉ hình tam giác nhọn màu vàng (#FFD60A) cố định ở đỉnh 12h (góc 0°)
                    let pointerTopY = center.y - radius + 2.0
                    let pointerTipY = pointerTopY + 13.5
                    var pointer = Path()
                    pointer.move(to: CGPoint(x: center.x - 2.8, y: pointerTopY))
                    pointer.addLine(to: CGPoint(x: center.x + 2.8, y: pointerTopY))
                    pointer.addLine(to: CGPoint(x: center.x, y: pointerTipY))
                    pointer.closeSubpath()
                    context.fill(pointer, with: .color(Self.cameraYellow))
                }

                // 2. Các nhãn mốc tiêu cự (`0.5 / 13MM`, `1 / 26MM`, `2 / 52MM`, `3 / 77MM`, `10`) xoay nghiêng theo cung tròn
                ForEach(Self.iPhoneArcMajorStops) { stop in
                    let angleDeg = (log2(stop.factor) - currentLog) * Self.degreesPerOctave
                    if abs(angleDeg) <= 56.0 {
                        let rad = angleDeg * .pi / 180.0
                        let sinA = sin(rad)
                        let cosA = cos(rad)
                        let edgeFade = max(0.0, min(1.0, (56.0 - abs(angleDeg)) / 12.0))

                        // Khi mốc trắng tiến sát nhãn vàng chính giữa (như số 2 nằm cạnh 1.6x trong ảnh mẫu),
                        // thu nhỏ và làm mờ nhẹ số trắng để không bao giờ đè lên chữ vàng chính giữa
                        let distDeg = abs(angleDeg)
                        let numOpacity: Double = distDeg < 4.2 ? 0.0 : (distDeg < 11.0 ? 0.35 * edgeFade : 0.95 * edgeFade)
                        let numScale: CGFloat = distDeg < 11.0 ? 0.78 : 1.0

                        let rNum = radius - 35.0
                        let numPos = CGPoint(x: center.x + rNum * sinA, y: center.y - rNum * cosA)

                        Text(stop.label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(numOpacity))
                            .scaleEffect(numScale)
                            .rotationEffect(.degrees(angleDeg))
                            .position(numPos)

                        if let mmText = stop.mmText {
                            let rMM = radius - 55.0
                            let mmPos = CGPoint(x: center.x + rMM * sinA, y: center.y - rMM * cosA)
                            let mmOpacity: Double = distDeg < 3.5 ? 0.28 * edgeFade : 0.48 * edgeFade

                            Text(mmText)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(mmOpacity))
                                .rotationEffect(.degrees(angleDeg))
                                .position(mmPos)
                        }
                    }
                }

                // 3. Số Zoom hiện tại màu vàng (#FFD60A) nằm cố định ngay dưới kim chỉ 12h (ví dụ: `1.6x`)
                Text(formattedZoomText(currentZoom, includeX: true))
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.cameraYellow)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .position(x: center.x, y: center.y - radius + 36.0)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.76),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dragDist = hypot(value.translation.width, value.translation.height)
                        if zoomDragStartFactor == nil {
                            zoomDragStartFactor = camera.zoomFactor
                            lastZoomHapticStep = Int((camera.zoomFactor * 10).rounded())
                        }
                        guard dragDist > 2.0 else { return }
                        let base = zoomDragStartFactor ?? camera.zoomFactor
                        let logBase = log2(max(base, CameraService.minZoomFactor))
                        // Kéo ngón tay sang trái làm bánh xe quay ngược chiều kim đồng hồ -> tăng zoom (0.5 -> 1 -> 2 -> 10)
                        let deltaOctaves = -value.translation.width / 82.0
                        let rawTarget = pow(2.0, logBase + deltaOctaves)
                        applyInteractiveZoom(rawTarget, animated: false)
                    }
                    .onEnded { value in
                        let dragDist = hypot(value.translation.width, value.translation.height)
                        zoomDragStartFactor = nil
                        // Nếu người dùng chạm trực tiếp vào một mốc trên vòm (như 0.5, 1, 2, 3, 5, 10), nhảy mượt tới mốc đó
                        if dragDist <= 5.0 {
                            let dx = value.location.x - center.x
                            let dy = center.y - value.location.y
                            if dy > 20 {
                                let tappedAngleDeg = atan2(dx, dy) * 180.0 / .pi
                                let tappedZoom = pow(2.0, currentLog + (tappedAngleDeg / Self.degreesPerOctave))
                                // Nếu chạm gần mốc chính thì hít vào mốc chính
                                var snapped = min(max(tappedZoom, CameraService.minZoomFactor), CameraService.maxZoomFactor)
                                for stop in Self.iPhoneArcMajorStops {
                                    if abs(log2(snapped) - log2(stop.factor)) < 0.16 {
                                        snapped = stop.factor
                                        break
                                    }
                                }
                                lastZoomHapticStep = Int((snapped * 10).rounded())
                                Self.shutterFeedback.impactOccurred(intensity: 0.65)
                                pinchBaseZoom = snapped
                                camera.setZoom(snapped, animated: true)
                            }
                        }
                        scheduleZoomWheelAutoCollapse(after: 1.6)
                    }
            )
        }
        .frame(height: 192)
        .frame(maxWidth: 440)
    }

    // MARK: - Pose Dial (Chạm để chọn dáng, Giữ im để mở thẻ chi tiết & gợi ý tạo dáng)

    private var poseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ShootingPose.all) { pose in
                        let isSelected = selectedPoseID == pose.id
                        HStack(spacing: 5) {
                            Image(systemName: pose.stance == .standing ? "figure.stand" : "chair.lounge.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? .black.opacity(0.75) : .white.opacity(0.65))

                            Text(pose.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.88))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "activePoseDial", in: poseNamespace)
                            } else {
                                Capsule()
                                    .fill(Color.black.opacity(0.38))
                            }
                        }
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                            }
                        }
                        .contentShape(Capsule())
                        .onTapGesture {
                            if activeDrawer != nil {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                    if case .poseInspector = activeDrawer {
                                        activeDrawer = .poseInspector(pose)
                                    } else {
                                        activeDrawer = nil
                                    }
                                }
                            }
                            guard selectedPoseID != pose.id else { return }
                            triggerSelectionHaptic()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedPoseID = pose.id
                                autoDecider.reset()
                                autoProgress = 0
                                proxy.scrollTo(pose.id, anchor: .center)
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.22) {
                            triggerShutterHaptic()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedPoseID = pose.id
                                autoDecider.reset()
                                autoProgress = 0
                                activeDrawer = .poseInspector(pose)
                                proxy.scrollTo(pose.id, anchor: .center)
                            }
                        }
                        .id(pose.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(selectedPoseID, anchor: .center)
            }
        }
    }

    // MARK: - Contextual Floating Drawers (Leica LUX / Halide / SOVS UX)

    @ViewBuilder
    private func contextualBottomDrawer(_ drawer: ActiveDrawer) -> some View {
        switch drawer {
        case .moodPalette:
            moodPaletteDrawer
        case .smartAssist:
            smartAssistDrawer
        case .poseInspector(let pose):
            poseInspectorDrawer(pose)
        case .modeSelector:
            EmptyView()
        }
    }

    /// Khay Bảng Màu Phim (hiện khi Giữ im hoặc bấm mở rộng nút Tone màu).
    private var moodPaletteDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bảng Tone Màu Phim", systemImage: "SwatchPalette")
                    .labelStyle(.titleOnly)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Text("· \(mood.subtitle)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mood.accentColor)
                Spacer()
                Button {
                    triggerSelectionHaptic()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeDrawer = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(Mood.allCases) { item in
                    let isSelected = (mood == item)
                    Button {
                        triggerSelectionHaptic()
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                            mood = item
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(item.swatchGradient)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? Color.white : Color.white.opacity(0.25),
                                                lineWidth: isSelected ? 2.2 : 0.8
                                            )
                                    }

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                                }
                            }

                            Text(item.title)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                                .lineLimit(1)

                            Text(item.shortTag)
                                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                                .foregroundStyle(isSelected ? item.accentColor : .white.opacity(0.45))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? item.accentColor.opacity(0.65) : Color.white.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    /// Khay Trợ Lý Dáng 3D & Chụp Tự Động (hiện khi Giữ im nút "Góc đẹp" hoặc nút "3D Figure").
    private var smartAssistDrawer: some View {
        let heightPresets: [Int] = [155, 160, 165, 170, 175, 180]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.netGreen)
                    Text("Tuỳ Chỉnh Mẫu 3D & Bố Cục AI")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button {
                    triggerSelectionHaptic()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeDrawer = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            // 1. Chiều cao người mẫu (lưu vào UserSettingsStore để co giãn tỷ lệ mẫu 3D chuẩn xác)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Chiều cao người mẫu")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            updateUserHeight(meters: max(1.45, currentHeightMeters - 0.02))
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)

                        Text("\(currentHeightCm) cm")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.netGreen)
                            .monospacedDigit()

                        Button {
                            updateUserHeight(meters: min(2.00, currentHeightMeters + 0.02))
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(heightPresets, id: \.self) { cm in
                        let isSelected = abs(currentHeightCm - cm) <= 2
                        Button {
                            updateUserHeight(meters: CGFloat(cm) / 100.0)
                        } label: {
                            Text("\(cm)")
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.white : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 2. Thanh trượt Zoom mượt (1.0× - 5.0× · 24mm - 120mm)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tiêu cự ống kính (Zoom)")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text("\(formattedZoomText(camera.zoomFactor, includeX: true)) · \(equivalentFocalLengthMM(camera.zoomFactor)) mm")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.cameraYellow)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { camera.zoomFactor },
                        set: { newValue in
                            applyInteractiveZoom(newValue, animated: false)
                        }
                    ),
                    in: CameraService.minZoomFactor...CameraService.maxZoomFactor,
                    step: 0.05
                )
                .tint(Self.cameraYellow)
            }

            // 3. Nút bật/tắt Tự chụp khi khớp dáng + Quét lại góc đẹp
            HStack(spacing: 8) {
                Button {
                    triggerSelectionHaptic()
                    autoCaptureEnabled.toggle()
                    if !autoCaptureEnabled {
                        autoDecider.reset()
                        autoProgress = 0
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: autoCaptureEnabled ? "timer.circle.fill" : "timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(autoCaptureEnabled ? Color.netGreen : .white.opacity(0.6))
                        Text(autoCaptureEnabled ? "Tự chụp AI: Bật" : "Tự chụp AI: Tắt")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        autoCaptureEnabled ? Color.netGreen.opacity(0.18) : Color.white.opacity(0.07),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            autoCaptureEnabled ? Color.netGreen.opacity(0.55) : Color.white.opacity(0.14),
                            lineWidth: 0.7
                        )
                    }
                }
                .buttonStyle(.plain)

                Button {
                    triggerShutterHaptic()
                    if mode.usesBodyTemplate {
                        if let layout {
                            pinchBaseZoom = layout.suggestedZoom
                            camera.setZoom(layout.suggestedZoom, animated: true)
                        }
                        camera.requestFloorAnchor(at: .zero)
                    } else {
                        pinchBaseZoom = 1.0
                        camera.setZoom(1.0, animated: true)
                    }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeDrawer = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Quét góc đẹp")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    /// Thẻ Chi Tiết Tư Thế (hiện khi Giữ im vào một dáng trên thanh Pose Strip).
    private func poseInspectorDrawer(_ pose: ShootingPose) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: pose.stance == .standing ? "figure.stand" : "chair.lounge.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.netGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pose.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("· Dáng \(pose.stance.title.lowercased())")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.netGreen)
                }
                Text(pose.cue)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                triggerSelectionHaptic()
                if let layout {
                    camera.setZoom(layout.suggestedZoom, animated: true)
                }
                camera.requestFloorAnchor(at: .zero)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    activeDrawer = nil
                }
            } label: {
                Text("Căn mẫu")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    /// Khay Chọn Chế Độ Chụp & Gợi Ý Bố Cục (hiện dưới Top Bar khi bấm/giữ nút NÉT · Chế độ).
    private var modeSelectorDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { item in
                    let isSelected = (camera.mode == item)
                    Button {
                        triggerSelectionHaptic()
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                            camera.mode = item
                            activeDrawer = nil
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.88))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? Color.white : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Gợi ý công thức góc máy cho chế độ hiện tại
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentRecipe.title): \(currentRecipe.direction)")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(currentRecipe.cameraTip)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    triggerSelectionHaptic()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        mood = currentRecipe.suggestedMood
                        activeDrawer = nil
                    }
                } label: {
                    Text("Màu \(currentRecipe.suggestedMood.title)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(currentRecipe.suggestedMood.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func updateUserHeight(meters: CGFloat) {
        let clamped = min(max(meters, 1.40), 2.05)
        triggerSelectionHaptic()
        UserSettingsStore.saveHeight(clamped)
        userHeight = UserHeight(meters: clamped, confirmedAt: Date())
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

            if !(GuideCamera.supportsRealSpaceAR && camera.position == .back && mode.usesBodyTemplate) {
                CameraPreview(camera: camera)
                    .scaleEffect(max(camera.zoomFactor, 1.0))
                    .clipped()
                    .ignoresSafeArea()
            }

            templateOverlay
                .ignoresSafeArea()

            // Lớp phủ xem trước Tone màu trực tiếp trên khung ngắm (Live Look Grading Preview)
            if mood != .natural {
                mood.viewfinderTint
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if showGrid {
                GridOverlay()
                    .ignoresSafeArea()
            }

            // Vòng ngắm phản hồi trực quan khi chạm lấy nét / đặt mẫu 3D trên sàn
            if let point = tapReticlePoint {
                FocusReticleView()
                    .id(tapReticleID)
                    .position(point)
                    .allowsHitTesting(false)
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
                if activeDrawer != nil {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeDrawer = nil
                    }
                    return
                }
                guard camera.isReady else { return }
                triggerSelectionHaptic()
                showTapReticle(at: value.location)
                camera.focus(atLayerPoint: value.location)
                let h = max(viewportSize.height, 844)
                if value.location.y > h * 0.16 && value.location.y < h * 0.77 {
                    camera.requestFloorAnchor(at: value.location)
                }
            }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    if !isZoomWheelExpanded {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            isZoomWheelExpanded = true
                        }
                    }
                    let target = min(max(pinchBaseZoom * scale, CameraService.minZoomFactor), CameraService.maxZoomFactor)
                    applyInteractiveZoom(target, animated: false)
                }
                .onEnded { _ in
                    pinchBaseZoom = camera.zoomFactor
                    scheduleZoomWheelAutoCollapse(after: 1.3)
                }
        )
    }

    private func showTapReticle(at point: CGPoint) {
        let currentID = UUID()
        tapReticleID = currentID
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            tapReticlePoint = point
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            if tapReticleID == currentID {
                withAnimation(.easeOut(duration: 0.2)) {
                    tapReticlePoint = nil
                }
            }
        }
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

    // MARK: - Bottom Control Bar (Nút Shutter khoá cứng chính giữa 100%, không bao giờ xê dịch khi đổi Tone màu; Góc đẹp chạm 1 lần để tuỳ chỉnh)

    private var bottomControls: some View {
        ZStack {
            // 1. Cụm hai bên (Trái: Bộ sưu tập + Tone màu | Phải: Góc đẹp)
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        triggerSelectionHaptic()
                        activeDrawer = nil
                        showGallery = true
                    } label: {
                        ZStack {
                            if let captured = camera.lastCapture {
                                Image(uiImage: captured.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 42, height: 42)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.black.opacity(0.42))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 15.5, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.88))
                                    }
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)

                    // Nút Tone Màu Phim: Chiều rộng cố định (94pt) để không bao giờ giãn/co hay đẩy nút Shutter
                    HStack(spacing: 5) {
                        Circle()
                            .fill(mood.swatchGradient)
                            .frame(width: 13, height: 13)
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
                            }

                        Text(mood.title)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: activeDrawer == .moodPalette ? "chevron.down" : "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(width: 96)
                    .background(
                        activeDrawer == .moodPalette ? Color.white.opacity(0.18) : Color.black.opacity(0.42),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            activeDrawer == .moodPalette ? mood.accentColor.opacity(0.75) : Color.white.opacity(0.18),
                            lineWidth: 0.8
                        )
                    }
                    .scaleEffect(isMoodLongPressing ? 0.94 : 1.0)
                    .contentShape(Capsule())
                    .onTapGesture {
                        triggerSelectionHaptic()
                        if activeDrawer == .moodPalette {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                activeDrawer = nil
                            }
                        } else {
                            let all = Mood.allCases
                            if let idx = all.firstIndex(of: mood) {
                                mood = all[(idx + 1) % all.count]
                            }
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.18, pressing: { pressing in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isMoodLongPressing = pressing
                        }
                    }) {
                        triggerShutterHaptic()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                            activeDrawer = (activeDrawer == .moodPalette) ? nil : .moodPalette
                        }
                    }
                }

                Spacer(minLength: 88)

                // Cụm bên phải: Chỉ cần chạm (ấn vô) "Góc đẹp" là mở ngay bảng tuỳ chỉnh Góc đẹp & Mẫu 3D!
                Button {
                    triggerSelectionHaptic()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        activeDrawer = (activeDrawer == .smartAssist) ? nil : .smartAssist
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: match.isAligned ? "checkmark.circle.fill" : "sparkles")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(match.isAligned ? "Đã khớp" : "Góc đẹp")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: activeDrawer == .smartAssist ? "chevron.down" : "slider.horizontal.3")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .foregroundStyle(match.isAligned ? Color.netGreen : .white.opacity(0.94))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        activeDrawer == .smartAssist ? Color.white.opacity(0.18) : Color.black.opacity(0.42),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            match.isAligned
                                ? Color.netGreen.opacity(0.6)
                                : (activeDrawer == .smartAssist ? Color.white.opacity(0.45) : Color.white.opacity(0.18)),
                            lineWidth: 0.8
                        )
                    }
                }
                .buttonStyle(.plain)
            }

            // 2. Nút Shutter đôi chuẩn Pro Camera: Neo cứng ở tâm ZStack (X = 50%), tuyệt đối không dịch chuyển!
            Button {
                triggerShutterHaptic()
                activeDrawer = nil
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

// MARK: - Focus & Floor Anchor Reticle (Pro Camera Visual Feedback)

private struct FocusReticleView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.netGreen.opacity(0.92), lineWidth: 1.6)
                .frame(width: 58, height: 58)

            Circle()
                .fill(Color.netGreen)
                .frame(width: 5, height: 5)
        }
        .scaleEffect(appeared ? 1.0 : 1.38)
        .opacity(appeared ? 1.0 : 0.25)
        .onAppear {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }
}

// MARK: - Pro Camera UI Metadata Extensions (Leica LUX / Apple Tone Styles)

extension CaptureMode {
    var iconName: String {
        switch self {
        case .solo: "person.fill"
        case .couple: "person.2.fill"
        case .group: "person.3.fill"
        case .object: "cube.fill"
        }
    }
}

extension Mood {
    var shortTag: String {
        switch self {
        case .natural: "Nguyên bản"
        case .film: "Điện ảnh"
        case .warm: "Nắng vàng"
        case .cool: "Sắc lạnh"
        case .vintage: "Hoài niệm"
        }
    }

    var subtitle: String {
        switch self {
        case .natural: "Màu trung tính chân thực"
        case .film: "Tương phản sâu kiểu phim nhựa"
        case .warm: "Da hồng ấm áp dưới nắng chiều"
        case .cool: "Trong vắt, sắc lạnh hiện đại"
        case .vintage: "Phủ nâu bạc màu hoài cổ"
        }
    }

    var accentColor: Color {
        switch self {
        case .natural: Color(red: 0.92, green: 0.93, blue: 0.96)
        case .film: Color(red: 0.38, green: 0.82, blue: 0.64)
        case .warm: Color(red: 0.98, green: 0.72, blue: 0.36)
        case .cool: Color(red: 0.44, green: 0.80, blue: 0.98)
        case .vintage: Color(red: 0.88, green: 0.66, blue: 0.46)
        }
    }

    var swatchGradient: LinearGradient {
        switch self {
        case .natural:
            LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .film:
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.68, blue: 0.54), Color(red: 0.08, green: 0.24, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warm:
            LinearGradient(
                colors: [Color(red: 0.99, green: 0.76, blue: 0.32), Color(red: 0.86, green: 0.40, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cool:
            LinearGradient(
                colors: [Color(red: 0.48, green: 0.86, blue: 0.99), Color(red: 0.20, green: 0.44, blue: 0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vintage:
            LinearGradient(
                colors: [Color(red: 0.88, green: 0.72, blue: 0.50), Color(red: 0.46, green: 0.32, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Lớp phủ màu cực nhẹ trên khung ngắm để người dùng cảm nhận ngay chất màu trước khi bấm chụp.
    var viewfinderTint: Color {
        switch self {
        case .natural: .clear
        case .film: Color(red: 0.12, green: 0.28, blue: 0.24).opacity(0.06)
        case .warm: Color(red: 0.98, green: 0.66, blue: 0.24).opacity(0.07)
        case .cool: Color(red: 0.28, green: 0.68, blue: 0.98).opacity(0.06)
        case .vintage: Color(red: 0.76, green: 0.56, blue: 0.30).opacity(0.08)
        }
    }
}
