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
    @State private var isMoodLongPressing = false
    @State private var isSmartSpotLongPressing = false
    @State private var isModeLongPressing = false

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

                // Hàng trạng thái thông minh: Chỉ dẫn AI 1 dòng + Nút chuyển nhanh tiêu cự (1x / 1.5x / 2x)
                HStack(spacing: 8) {
                    QualityCoachOverlay(check: check)
                    focalLengthDial
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

                // Dải chọn tư thế mỏng đặt ngay trên nút chụp (chuẩn Pro Camera, Giữ im để xem chi tiết dáng)
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

    // MARK: - Focal Length Dial (1x · 1.5x · 2x chuẩn Halide / iPhone Pro Camera)

    private var focalLengthDial: some View {
        let presets: [(label: String, factor: CGFloat)] = [
            ("1x", 1.0),
            ("1.5x", 1.5),
            ("2x", 2.0)
        ]
        return HStack(spacing: 3) {
            ForEach(presets, id: \.label) { preset in
                let isSelected = abs(camera.zoomFactor - preset.factor) < 0.22
                Button {
                    triggerSelectionHaptic()
                    camera.setZoom(preset.factor, animated: true)
                } label: {
                    Text(preset.label)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        }
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

            // 2. Nút bật/tắt Tự chụp khi khớp dáng + Quét lại góc đẹp
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
                    if let layout {
                        camera.setZoom(layout.suggestedZoom, animated: true)
                    }
                    camera.requestFloorAnchor(at: .zero)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeDrawer = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Quét lại góc đẹp")
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

            CameraPreview(camera: camera)
                .ignoresSafeArea()

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
                    let target = min(max(pinchBaseZoom * scale, 1.0), 4.0)
                    camera.setZoom(target, animated: false)
                }
                .onEnded { _ in
                    pinchBaseZoom = camera.zoomFactor
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

    // MARK: - Bottom Control Bar (Tinh gọn: Bộ sưu tập | Màu phim (Giữ im mở bảng) | Shutter | Góc đẹp (Giữ im mở cài đặt 3D))

    private var bottomControls: some View {
        HStack(alignment: .center) {
            // Cụm bên trái: Nút Bộ sưu tập & Nút Tone màu (Chạm đổi nhanh, Giữ im mở Bảng 5 Tone Màu)
            HStack(spacing: 10) {
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

                // Nút Tone Màu Phim (Mood): Chạm để đổi nhanh, Giữ im (hoặc bấm mũi tên) để mở Bảng 5 Tone Màu
                HStack(spacing: 6) {
                    Circle()
                        .fill(mood.swatchGradient)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
                        }

                    Text(mood.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    Image(systemName: activeDrawer == .moodPalette ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerShutterHaptic()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                activeDrawer = (activeDrawer == .moodPalette) ? nil : .moodPalette
                            }
                        }
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
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
                .scaleEffect(isMoodLongPressing ? 0.92 : 1.0)
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
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mood = all[(idx + 1) % all.count]
                            }
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // Nút Shutter đôi chuẩn Pro Camera
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

            // Cụm bên phải: Chạm để tự quét góc đứng đẹp nhất, Giữ im để mở Tuỳ chỉnh Chiều cao 3D & Tự chụp AI
            HStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: match.isAligned ? "checkmark.circle.fill" : "sparkles")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(match.isAligned ? "Đã khớp" : "Góc đẹp")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: activeDrawer == .smartAssist ? "chevron.down" : "slider.horizontal.3")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .fixedSize(horizontal: true, vertical: false)
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
                .scaleEffect(isSmartSpotLongPressing ? 0.92 : 1.0)
                .contentShape(Capsule())
                .onTapGesture {
                    triggerSelectionHaptic()
                    if activeDrawer == .smartAssist {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            activeDrawer = nil
                        }
                        return
                    }
                    if mode.usesBodyTemplate {
                        if let layout {
                            camera.setZoom(layout.suggestedZoom, animated: true)
                        }
                        camera.requestFloorAnchor(at: .zero)
                    } else {
                        camera.setZoom(1.0, animated: true)
                        let center = CGPoint(x: max(viewportSize.width, 390) * 0.5, y: max(viewportSize.height, 844) * 0.5)
                        camera.focus(atLayerPoint: center)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.18, pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isSmartSpotLongPressing = pressing
                    }
                }) {
                    triggerShutterHaptic()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                        activeDrawer = (activeDrawer == .smartAssist) ? nil : .smartAssist
                    }
                }
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
