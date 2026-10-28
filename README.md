# NET (NET_ver1) — iOS AR Pose Guidance & Real-Time Posture Coaching

An iOS camera application that projects life-size 3D human pose templates onto real-world floor surfaces and coaches users into portrait poses using on-device computer vision. Built with **Swift 6**, **SwiftUI**, **ARKit**, **RealityKit**, and the **Vision** framework.

---

## Key Features

- **Real-World Floor Anchoring & Smart Auto-Placement (`SceneComposer`, `CameraView`)**
  - Detects horizontal floor planes via `ARWorldTrackingConfiguration`.
  - Evaluates 15 candidate positions across open floor space to automatically place the 3D mannequin at an optimal rule-of-thirds composition point.
- **Life-Size 3D Pose Templates (`FigureAssetLoader`, `FigureBuilders`, `FurnitureBuilder`)**
  - Ships with static baked `.usdz` 3D character meshes (`pose-standing-straight`, `pose-standing-hip`, `pose-standing-aside`, `pose-seated-straight`, `pose-seated-lean`, `pose-seated-chin`).
  - Procedural contact shadows (`GroundShadowBuilder`), translucent shader materials (`FigureMaterial`), and smooth quaternion/vector interpolation (`simd_mix` & `simd_slerp`) rotated at a natural 3/4 angle toward the camera lens.
- **On-Device Posture Matching & Auto-Capture (`FrameAnalyzer`, `PostureMatch`, `AutoCapture`)**
  - Runs real-time 2D/3D skeletal pose estimation using Apple's `Vision` framework directly on the Neural Engine.
  - Computes joint-angle similarity, framing safety (`SafeArea`), and lighting quality (`CaptureCheck`, `QualityCoachOverlay`) to trigger hands-free shutter capture when the subject matches the target pose.
- **Minimalist Pro Camera Interface (`CameraChrome`, `GalleryView`)**
  - Edge-to-edge viewfinder, frosted glass controls, rule-of-thirds grid overlay (`GridOverlay`), film mood presets, and full layout support for both iPhone and iPad.

---

## Architecture & Tech Stack

The codebase follows **Clean Architecture** with **Swift 6 Strict Concurrency** (`@MainActor` UI isolation and thread-safe background frame analysis):

```text
NET_ver1/
├── App/
│   ├── NetApp.swift                # Application entry point & lifecycle
│   └── RootView.swift              # Root navigation & permission flow
├── Cores/
│   ├── CameraService.swift         # AVFoundation & ARSession capture pipeline
│   ├── FrameAnalyzer.swift         # Vision framework skeletal pose extraction
│   ├── AnalysisConfiguration.swift # Frame throttling & confidence thresholds
│   ├── GridOverlay.swift           # Rule-of-thirds & composition overlays
│   ├── NetColors.swift             # Design system color tokens
│   └── PhotoLibraryAuth.swift      # Photos framework authorization handler
├── Domain/
│   ├── PoseTemplate.swift          # Pose metadata & joint angle definitions
│   ├── PostureMatch.swift          # Cosine/Euclidean skeletal matching engine
│   ├── AutoCapture.swift           # Stability timer & auto-shutter state machine
│   ├── SceneComposer.swift         # AR raycasting & 15-point floor scoring
│   ├── FigureAssetLoader.swift     # Asynchronous USDZ entity loader & wrapper
│   ├── FigureMaterial.swift        # Translucent RealityKit material generator
│   └── CaptureCheck.swift          # Exposure, framing, and distance evaluator
├── Features/
│   ├── CameraView.swift            # Main AR camera viewport
│   ├── CameraChrome.swift          # Shutter, pose carousel, and HUD controls
│   ├── QualityCoachOverlay.swift   # Real-time posture & composition feedback pill
│   ├── BodyTemplateOverlay.swift   # 2D skeletal alignment overlay
│   └── GalleryView.swift           # In-app photo review & comparison
└── Assets/Resources/               # Baked 3D USDZ pose models
```

| Layer | Technologies |
|---|---|
| **Language & Concurrency** | Swift 6, Swift Concurrency (`async/await`, Actors) |
| **UI Framework** | SwiftUI |
| **Augmented Reality & 3D** | ARKit (`ARWorldTrackingConfiguration`), RealityKit, USDZ |
| **Computer Vision** | Apple Vision Framework (`VNDetectHumanBodyPoseRequest`) |
| **Media & Storage** | AVFoundation, PhotosUI / PHPhotoLibrary |
| **Testing** | XCTest (`Tests/`) |

---

## Getting Started

### Prerequisites
- **macOS** with **Xcode 16.0+**
- **Physical iPhone or iPad** running **iOS 17.0+** (ARKit world tracking and rear camera feed require a physical device with an A12 Bionic chip or newer).

### Installation & Run
1. Clone the repository:
   ```bash
   git clone https://github.com/VoHoang07/NET_ver1.git
   cd NET_ver1
   ```
2. Open the project in Xcode:
   ```bash
   open NET_ver1.xcodeproj
   ```
3. In Xcode, select the **NET_ver1** target -> **Signing & Capabilities**, and choose your Apple Development Team.
4. Connect your iPhone/iPad, select it as the run destination, and press **Cmd + R** to build and launch.
5. Run unit tests via **Cmd + U** or CLI:
   ```bash
   xcodebuild test -project NET_ver1.xcodeproj -scheme NET_ver1 -destination 'platform=iOS Simulator,name=iPhone 16'
   ```

---

## License & Privacy

- **Privacy:** All camera frames and skeletal pose computations execute 100% on-device. No images or biometric data ever leave the user's device. See [docs/PRIVACY-POLICY.md](docs/PRIVACY-POLICY.md).
- **Author:** Vo Vu Minh Hoang ([@VoHoang07](https://github.com/VoHoang07))
