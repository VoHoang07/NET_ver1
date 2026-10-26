# Nhật Ký Theo Dõi & Xử Lý Bug (Bug Log & Post-Mortem)

Tài liệu này lưu trữ toàn bộ các lỗi (bugs), sự cố kỹ thuật, và các "lỗi im lặng" (silent bugs) đã từng gặp phải trong quá trình phát triển dự án **NET_ver1**, cùng với dòng thông báo lỗi gốc bằng tiếng Anh (compiler error, runtime crash, hoặc XCTest assertion message), nguyên nhân gốc rễ, giải pháp khắc phục và bài kiểm tra (regression tests) phòng ngừa.

> **Quy định tự động ghi nhận (Auto-Logging Rule):**
> Mỗi khi phát hiện, xử lý hoặc điều tra một lỗi mới (kể cả lỗi compile, lỗi runtime, lỗi 3D rendering, lỗi logic hay thuật toán), AI Agent và lập trình viên **bắt buộc tự động cập nhật** thêm mục lỗi mới vào tài liệu này theo đúng định dạng chuẩn ở cuối file, kèm theo **thông báo lỗi gốc bằng tiếng Anh**.

---

## Danh Sách Tổng Hợp Nhanh (Bug Matrix)

| Mã ID | Phân Loại | Mức Độ | Tóm Tắt Sự Cố | Trạng Thái | Unit Test Chặn Lại |
|---|---|---|---|---|---|
| **BUG-001** | Asset 3D / USDZ | Nghiêm trọng | Ghép 6 clip vào 1 file USDZ khiến RealityKit trả về animation rỗng | Đã sửa | N/A (Bake mesh tĩnh) |
| **BUG-002** | Asset 3D / Blender | Nghiêm trọng | Blender 4.4+ thiếu `action_slot` khiến cả 6 pose nướng ra cùng 1 dáng | Đã sửa | `testPosesAreActuallyDifferent` |
| **BUG-003** | Asset 3D / Blender | Cao | Lệnh `transforms_clear` xoá bỏ pose, đưa người mẫu về T-pose | Đã sửa | `testPosesAreActuallyDifferent` |
| **BUG-004** | Asset 3D / USDZ | Nghiêm trọng | Lỗi căn lề byte (64-byte alignment) làm RealityKit từ chối nạp USDZ | Đã sửa | `testEveryPoseHasBundledFile` |
| **BUG-005** | Asset 3D / Blender | Nghiêm trọng | `convert_orientation=True` làm người 3D bị xoay nằm ngang | Đã sửa | `testFigureIsUprightAfterRealityKitLoad` |
| **BUG-006** | Asset 3D / Mixamo | Cao | Lọt mesh khớp xương `Beta_Joints` gây hiện tượng "búp bê tháo rời" | Đã sửa | `testOnlySkinMeshIsShipped` |
| **BUG-007** | Asset 3D / Exporter | Trung bình | Xuất dạng văn bản `.usda` làm dung lượng phình to 4.5 lần | Đã sửa | `testFileSizeIsPlausible` |
| **BUG-008** | Asset 3D / Scene | Nghiêm trọng | Lệch toạ độ gốc (X, Z) giữa các clip làm người 3D bay khỏi khung nhìn | Đã sửa | `testFigureIsCentredSidewaysAndDepth` |
| **BUG-009** | RealityKit / Camera | Cao | Truyền ngược tham số `camera.look(at:from:)` làm lộn ngược người | Đã sửa | `testFigureIsUprightNotInverted` |
| **BUG-010** | RealityKit / Model | Nghiêm trọng | Gán `entity.scale` trực tiếp lên root entity USDZ bị bỏ qua âm thầm | Đã sửa | `testScaleActuallyApplies` |
| **BUG-011** | Domain / Scaling | Cao | Tính chiều cao đầu bằng `chiều_cao / 7.5` làm dáng ngồi phình to 128% | Đã sửa | `testEveryPoseUsesTheSameScaleFactor` |
| **BUG-012** | RealityKit / View | Cao | Camera ngắm theo đường mắt 1/3 làm nửa dưới người mẫu bị cắt cụt | Đã sửa | `testFigureFitsInsideFrame` |
| **BUG-013** | RealityKit / Material | Trung bình | `PhysicallyBasedMaterial` mặc định `.opaque` bỏ qua alpha màu | Đã sửa | `testMaterialIsActuallyTransparent` |
| **BUG-014** | RealityKit / Lighting | Trung bình | Thiếu nguồn sáng đa hướng làm bóng người 3D phẳng lì như ảnh dán | Đã sửa | `TranslucentSceneView.makeTestLights` |
| **BUG-015** | iOS 18 / RealityView | Nghiêm trọng | `RealityView` bỏ qua `PerspectiveCamera`, làm hỏng khung hình trên iOS 18 | Đã sửa | `testRealityViewBranchFramesTheFigure` |
| **BUG-016** | Concurrency | Nghiêm trọng | `assumeIsolated` từ background queue gây crash runtime ngay frame đầu | Đã sửa | `AnalysisConfigurationTests` |
| **BUG-017** | Camera / Zoom | Trung bình | Rung lắc khi zoom xa và giật hình khi tự động chọn mức zoom | Đã sửa | Bật chống rung, smooth AF, ramp rate |
| **BUG-018** | UI / Coaching | Thấp | Báo nhiều lỗi kỹ thuật cùng lúc gây nhiễu và che khuất khung ngắm | Đã sửa | Lọc 1 lỗi cấp thiết nhất, dùng động từ |
| **BUG-019** | Vision / SafeArea | Cao | Trộn lẫn trục toạ độ khi tính tỉ lệ `resizeAspectFill` sai lệch 30% | Đã sửa | `SafeAreaTests`, `SceneComposerTests` |
| **BUG-020** | Domain / AutoCapture | Trung bình | AutoCapture bấm chụp khi người mẫu vừa cử động hoặc chưa đủ yên | Đã sửa | `AutoCaptureTests` (1.2s stillness) |
| **BUG-021** | RealityKit / Scene | Cao | Khối bàn ghế hộp (`FurnitureBuilder`) đặt ngược chiều `+Z` chắn trước mặt người mẫu | Đã sửa | `testGuideSceneDoesNotIncludeFurnitureBoxes` |
| **BUG-022** | RealityKit / View & State | Nghiêm trọng | `RealityView` nhìn vào gốc `(0,0,0)` đẩy người lên nửa trên, kẹt màu xanh lá và không đổi tư thế | Đã sửa | `testEmptyMeasurementsAreNotAligned` |
| **BUG-023** | Asset 3D / Material | Cao | Mesh `Beta_Surface` bị hở cổ, rỗng vùng bụng/eo và lộ vách ngăn nội bộ như người máy | Đã sửa | `testFigureMaterialUsesBackFaceCullingAndHumanSkinTone` |
| **BUG-024** | RealityKit / CoreMotion | Cao | Người mẫu 3D gắn cứng vào khung màn hình 2D thay vì phản ứng theo góc nghiêng/lia máy | Đã sửa | `testSpatialCameraReactsToTiltPanAndZoom` |
| **BUG-025** | ARKit / RealityKit | Nghiêm trọng | Người mẫu 3D bay lơ lửng giữa không trung vì thiếu nhận diện mặt sàn thực (`ARPlaneAnchor`) và thiếu bóng đổ sàn | Đã sửa | `testFloorAnchorTransformPinsFeetToDetectedFloorY`, `testGroundShadowBuilderCreatesFloorShadowAtGroundLevel` |
| **BUG-026** | ARKit / Anchoring & UX | Cao | Fallback mặt phẳng ảo (`camY - 1.20`) làm mẫu 3D trôi theo ống kính khi chưa quét xong sàn, thiếu `ARTrackedRaycast`, thiếu `ARCoachingOverlayView` và huỷ `ARSession` khi ẩn/hiện mẫu | Đã sửa | `testShouldAcceptFloorRaycastHitRejectsElevatedOrOutOfRangeHits`, `testAmbientLightFactorScalesAndClampsSceneLighting` |
| **BUG-027** | RealityKit / Shadow & Pro Camera UI | Cao | Mesh chữ nhật màu xám nhân tạo (`floor-contact-shadow` & `floor-projected-silhouette`) dưới chân mẫu, thiếu thuật toán chọn góc đứng 1/3 + Lerp/Slerp, và khung ngắm UI bị co cụm 3:4 kèm popup lỗi trên Simulator | Đã sửa | `testGroundShadowBuilderCreatesFloorShadowAtGroundLevel`, `testSmartAutoPlacementHeuristicsAndSmoothing` |
| **BUG-028** | iOS 26 UI / RealityKit Occlusion & Framing | Cao | `OcclusionMaterial(receivesDynamicLighting: true)` rộng 3.6m tạo mảng xám cắt chéo sàn, mẫu 3D lệch sang rìa trái chạm thanh điều khiển trên, và iOS 26 Liquid Glass tự chèn vòng tròn nâu/viền đôi làm rối giao diện | Đã sửa | `testGroundShadowBuilderCreatesFloorShadowAtGroundLevel`, `testSmartAutoPlacementHeuristicsAndSmoothing` |

---

## Chi Tiết Từng Sự Cố Kỹ Thuật

### BUG-001: RealityKit không đọc được nhiều animation trong một file USDZ
- **Phân loại**: Asset 3D / USDZ Specification
- **Mức độ**: Nghiêm trọng (Lỗi im lặng - Silent Failure)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  [Silent Failure - Build Succeeded, No Runtime Warnings]
  Entity.load(contentsOf:) -> entity.availableAnimations is empty: []
  Assertion Check: XCTAssertGreaterThan(meshCount, 0, "Tư thế \(pose.id) không có mesh nào — sẽ không hiện gì")
  ```
- **Triệu chứng**: Ghép 6 clip animation vào cùng 1 file `.usdz`. File hoàn toàn hợp lệ, lệnh `usdcat` hiển thị đủ tên 6 clip, Xcode không báo lỗi, nhưng hàm `availableAnimations` trong RealityKit trả về mảng rỗng `[]`. Ứng dụng âm thầm rơi về fallback dựng hình khối.
- **Nguyên nhân gốc rễ**: Theo đặc tả OpenUSD, `SkelRoot` chỉ duy trì **duy nhất một** quan hệ `skel:animationSource` tới `SkelAnimation`. RealityKit đọc animation qua đúng quan hệ này, nên mỗi file chỉ kích hoạt được 1 animation duy nhất.
- **Giải pháp**: Không dùng animation động. Chuyển sang chiến lược "nướng" (bake) từng tư thế thành mesh tĩnh riêng lẻ: mỗi pose là 1 file USDZ (`pose-<id>.usdz`), loại bỏ hoàn toàn bộ xương và đường cong animation.
- **Phòng ngừa & Test**: `FigureAssetLoader.load` nạp từng file độc lập; `testEveryPoseHasBundledFile` đảm bảo đủ 6 file USDZ trong bundle.

---

### BUG-002: Blender 4.4+ thiếu `action_slot` khiến cả 6 pose nướng ra cùng 1 dáng
- **Phân loại**: Tooling / Blender 4.4+ API Change
- **Mức độ**: Nghiêm trọng (Lỗi im lặng)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Tư thế \(pose.id) và \(other) cho ra hình hệt nhau — tư thế chưa thực sự được nướng"
  Diff signature check: signatures[boundsSignature(entity)] != nil
  ```
- **Triệu chứng**: Cả 6 file USDZ sau khi nướng có kích thước, mã băm (hash) và hình dáng hoàn toàn trùng khớp nhau. Quá trình export báo thành công, không có thông báo lỗi.
- **Nguyên nhân gốc rễ**: Kể từ Blender 4.4, hệ thống Action Slots được áp dụng. Khi gán `arm.animation_data.action = action` mà không gán slot tương ứng, action sẽ chạy trên slot rỗng, bộ xương không nhận keyframe và giữ nguyên trạng thái ban đầu.
- **Giải pháp**: Trong `tools/bake_poses.py`, kiểm tra và gán slot:
  ```python
  if hasattr(arm.animation_data, "action_slot") and len(action.slots) > 0:
      arm.animation_data.action_slot = action.slots[0]
  ```
- **Phòng ngừa & Test**: Viết unit test `testPosesAreActuallyDifferent` trong `FigureAssetTests.swift`: kiểm tra bounding box signature của 6 tư thế, bắt buộc phải khác nhau.

---

### BUG-003: Lệnh `transforms_clear` đưa tư thế về T-pose
- **Phân loại**: Tooling / Blender Scripting
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Tư thế \(pose.id) và \(other) cho ra hình hệt nhau — tư thế chưa thực sự được nướng"
  Visual defect: All figure meshes rendered in identical T-pose / Rest-pose geometry
  ```
- **Triệu chứng**: Sau khi nướng, tất cả 6 tư thế đều biến thành dáng đứng thẳng (T-pose/Rest pose).
- **Nguyên nhân gốc rễ**: Lệnh `bpy.ops.object.transforms_clear()` xoá toàn bộ biến đổi tư thế mà action vừa áp tại frame 40, đưa armature về tư thế gốc trước khi áp modifier.
- **Giải pháp**: Loại bỏ hoàn toàn `transforms_clear()`. Dùng `bpy.context.scene.frame_set(POSE_FRAME)` và gọi `bpy.ops.object.modifier_apply(modifier="Armature")`.
- **Phòng ngừa & Test**: Bị chặn tự động bởi `testPosesAreActuallyDifferent` và `FigureRenderTests`.

---

### BUG-004: USDZ vi phạm căn lề 64-byte làm RealityKit từ chối nạp
- **Phân loại**: Asset 3D / Định dạng USDZ Apple
- **Mức độ**: Nghiêm trọng
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  SystemExit: "USDZ khong dung chuan: du lieu bat dau tai byte <offset>, can boi so cua 64"
  RealityKit Runtime: [RealityFoundation] Failed to load USDZ: entry payload is not 64-byte aligned (Entity.load returned nil)
  ```
- **Triệu chứng**: Build sạch, test khác xanh, không log lỗi nào, nhưng `Entity.load(contentsOf:)` luôn trả về `nil`.
- **Nguyên nhân gốc rễ**: Chuẩn USDZ của Apple yêu cầu phần dữ liệu (payload data) của mỗi entry trong file zip phải bắt đầu tại vị trí byte là bội số của 64. Vị trí byte thực tế là `header_offset + 30 + len(filename) + len(extra)`. Script cũ chỉ kiểm tra `header_offset % 64 == 0` (luôn bằng 0 vì file chỉ có 1 entry ở đầu) nên không phát hiện ra phần dữ liệu thực tế bị lệch byte.
- **Giải pháp**: Tính toán độ dài padding và chèn vào trường `extra` của `zipfile.ZipInfo`, nén bằng `zipfile.ZIP_STORED`:
  ```python
  header_len = 30 + len(filename.encode("utf-8"))
  padding = (64 - header_len % 64) % 64
  if padding:
      info.extra = b"\xff\xff" + struct.pack("<H", padding - 4) + b"\x00" * (padding - 4)
  ```
- **Phòng ngừa & Test**: Kiểm tra tính hợp lệ bằng code đọc nhị phân ngay sau khi zip trong `bake_poses.py`; test `testEachPoseLoadsWithVisibleMesh` kiểm tra nạp thành công.

---

### BUG-005: `convert_orientation=True` làm người mẫu 3D nằm ngang
- **Phân loại**: Tooling / Blender USD Exporter
- **Mức độ**: Nghiêm trọng
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "\(pose.id): người NẰM NGANG — cao \(height) ≤ sâu \(depth). Kiểm tra `convert_orientation` trong `tools/bake_poses.py`."
  XCTAssertGreaterThan failed: (height: 0.54) is not greater than (depth: 1.70)
  ```
- **Triệu chứng**: Trên màn hình điện thoại, người 3D bị nằm ngang/nằm sấp dọc trục Z, bóng đầu và hông chồng lên nhau thành một khối tròn.
- **Nguyên nhân gốc rễ**: Blender dùng trục Z là trục đứng, USD quy ước trục Y là trục đứng. Khi bật `convert_orientation=True`, exporter của Blender tự thêm phép xoay `rotateXYZ = (-90, 0, 0)` tại prim root để bù toạ độ. Khi RealityKit đọc file có metadata `upAxis="Y"`, nó lại tự xoay một lần nữa -> hai phép biến đổi triệt tiêu lẫn nhau khiến hình học bị nằm ngang.
- **Giải pháp**: Đặt `convert_orientation=False` trong `bpy.ops.wm.usd_export`. Không xoay thủ công bằng code.
- **Phòng ngừa & Test**: `testFigureIsUprightAfterRealityKitLoad` đo trực tiếp kích thước bounding box sau khi RealityKit nạp: yêu cầu chiều cao $Y > Z$ (chiều sâu).

---

### BUG-006: Lọt mesh khớp xương `Beta_Joints` gây hiện tượng "búp bê tháo rời"
- **Phân loại**: Asset 3D / Mesh Structure Mixamo
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "\(pose.id) chứa \(names.count) mesh: \(names) — chỉ được có mesh da"
  XCTestFailure: "\(pose.id) vẫn chứa mesh xương: ["Beta_Surface", "Beta_Joints"]"
  ```
- **Triệu chứng**: Người 3D hiển thị các khối cầu mọc ra ở khớp vai, cùi chỏ, hông. Khi mất liên kết xương, các khối cầu này đứng ở T-pose lấn ra ngoài khung hình.
- **Nguyên nhân gốc rễ**: Model Mixamo chứa 2 mesh: `Beta_Surface` (da) và `Beta_Joints` (khối cầu biểu diễn khớp). Thiết lập `export_armatures=False` vẫn xuất mesh con nếu chúng vẫn tồn tại trong Scene.
- **Giải pháp**: Trong `bake_poses.py`, duyệt tìm và xoá hẳn tất cả object có tên chứa `"joints"` khỏi `bpy.data.objects`.
- **Phòng ngừa & Test**: `testOnlySkinMeshIsShipped` đếm số lượng `ModelComponent` trên Entity, khẳng định chỉ có duy nhất 1 mesh da và không chứa từ khoá "joint".

---

### BUG-007: Xuất file dạng văn bản `.usda` làm dung lượng phình to
- **Phân loại**: Hiệu năng & Dung lượng Bundle
- **Mức độ**: Trung bình
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "File của \(pose.id) quá lớn — nên xuất .usdc"
  XCTAssertLessThan failed: (bytes: 61482910) is not less than (8000000)
  ```
- **Triệu chứng**: Mỗi file model chiếm từ 61 MB trở lên, làm dung lượng app vượt quá giới hạn tải về từ App Store qua mạng di động.
- **Nguyên nhân gốc rễ**: Xuất ra định dạng USD dạng văn bản thô `.usda` trước khi đóng gói thành zip USDZ.
- **Giải pháp**: Xuất ra định dạng USD nhị phân (`.usdc`), giúp giảm dung lượng xuống còn dưới 13.6 MB (hoặc dưới 8 MB sau tối ưu).
- **Phòng ngừa & Test**: `testFileSizeIsPlausible` trong `FigureAssetTests` giới hạn kích thước mỗi file USDZ phải nằm trong khoảng $200\text{ KB} < \text{size} < 8\text{ MB}$.

---

### BUG-008: Lệch toạ độ gốc (Origin) giữa các clip làm người 3D bay khỏi khung nhìn
- **Phân loại**: Asset 3D / Transform Alignment
- **Mức độ**: Nghiêm trọng
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "\(pose.id) tâm X ở \(centreX), phải gần 0 — người lệch sang bên là trượt khỏi khung"
  XCTestFailure: "\(pose.id) tâm Z ở \(centreZ), phải gần 0 — người lệch ra sau là camera đứng sau lưng người"
  XCTestFailure: "`standing-aside`: ảnh chụp không thấy bóng người (pixel ấm=0)."
  ```
- **Triệu chứng**: Ở tư thế `standing-aside`, màn hình hoàn toàn trống không; ở tư thế `seated-straight`, chỉ thấy chiếc bàn mà không thấy người.
- **Nguyên nhân gốc rễ**: Mỗi clip Mixamo có toạ độ offset chuyển động nhân vật riêng. Khi xuất, `standing-aside` bị lệch trục X (+3.4 m) và Z (-3.7 m). Vì camera đặt tại $Z > 0$ nhìn về gốc toạ độ, nhân vật nằm tại $Z = -3.7\text{ m}$ đồng nghĩa với việc **camera nằm sau lưng người mẫu** và người mẫu trượt khỏi góc nhìn.
- **Giải pháp**: Trong `bake_poses.py`, duyệt qua toàn bộ đỉnh `all_vertices`, tính toán `centre_x`, `centre_y`, `lowest_z` và dịch chuyển trực tiếp toạ độ đỉnh về tâm $(0, 0, 0)$:
  ```python
  vertex.co.x -= centre_x
  vertex.co.y -= centre_y
  vertex.co.z -= lowest
  ```
- **Phòng ngừa & Test**: `testFigureIsCentredSidewaysAndDepth` khẳng định tâm X và Z phải xấp xỉ 0 (sai số $\le 0.01\text{ m}$). `testGuideFigureIsActuallyVisible` chụp snapshot thực tế để đếm số pixel người mẫu.

---

### BUG-009: Đảo ngược tham số trong `camera.look(at:from:)`
- **Phân loại**: RealityKit / Camera Transform
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "\(pose.id) cao=\(height) rộng=\(width) — có thể đang lộn ngược"
  RealityFoundation: Inverted camera orientation: forward vector points along +Z instead of -Z
  ```
- **Triệu chứng**: Hình ảnh người 3D bị quay ngược 180 độ, đầu cắm xuống sàn nhà, chân chổng lên trời.
- **Nguyên nhân gốc rễ**: Nhầm lẫn chữ ký hàm: `camera.look(at: target, from: position)` nhận tham số mục tiêu `at` trước, vị trí camera `from` sau. Khi truyền ngược lại, camera xoay 180 độ nhìn ra phía sau.
- **Giải pháp**: Đảm bảo truyền đúng `at: target` và `from: cameraPosition`.
- **Phòng ngừa & Test**: `testFigureIsUprightNotInverted` kiểm tra tỉ lệ bề rộng ở nửa trên (vai) và nửa dưới (chân) để đảm bảo đầu luôn ở trên.

---

### BUG-010: Gán `entity.scale` trực tiếp lên Entity nạp từ USDZ không có tác dụng
- **Phân loại**: RealityKit / Scene Graph Transform
- **Mức độ**: Nghiêm trọng (Lỗi im lặng)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Scale 1,5 không có tác dụng: trước=\(before) sau=\(after)"
  XCTAssertEqual failed: ("1.000") is not equal to ("1.500") +/- ("0.05")
  ```
- **Triệu chứng**: Hàm chuẩn hoá tỉ lệ `normalizeScale` chạy liên tục nhưng kích thước người mẫu trên màn hình không đổi, luôn giữ kích thước cố định của file gốc bất kể người dùng nhập chiều cao bao nhiêu.
- **Nguyên nhân gốc rễ**: Gán `scale` trực tiếp lên root entity nạp từ USDZ không truyền biến đổi xuống các prim con bên trong do cấu trúc phân cấp transform nội bộ của USD.
- **Giải pháp**: Tạo một `Entity` cha làm wrapper, gán model vào làm con, và áp dụng scale lên chính wrapper này:
  ```swift
  let wrapper = Entity()
  wrapper.addChild(entity)
  wrapper.scale = SIMD3<Float>(repeating: scaleFactor)
  ```
- **Phòng ngừa & Test**: `testScaleActuallyApplies` đo kích thước thực tế của wrapper trước và sau khi gán scale 1.5, kiểm tra tỉ lệ scale thay đổi đúng 150%.

---

### BUG-011: Tính chiều cao đầu bằng `chiều_cao / 7.5` làm dáng ngồi bị phình to 128%
- **Phân loại**: Thuật toán tỉ lệ nhân trắc học
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Mọi tư thế phải dùng cùng một hệ số scale"
  Calculated: headHeightRatio for seated pose = 0.177 vs standing pose = 0.240 (26% discrepancy, 1.28x overscale)
  ```
- **Triệu chứng**: Các tư thế ngồi (`seated-straight`, `seated-lean`) bị phóng to bất thường, thân người phình to, chân chiếm hết màn hình, đầu chạm đỉnh khung nhìn.
- **Nguyên nhân gốc rễ**: Quy tắc kinh điển "chiều cao người bằng 7.5 đầu" chỉ đúng với người đứng. Với người ngồi, tổng chiều cao thấp hơn (khoảng 1.33 m so với 1.80 m). Khi lấy `chiều_cao_ngồi / 7.5` sẽ ra chiều cao đầu là $0.177\text{ m}$ (sai lệch 26% so với đầu thật $0.240\text{ m}$), dẫn đến việc nhân hệ số phóng đại lên 1.28 lần.
- **Giải pháp**: Chiều cao đầu của một người là bất biến dù đứng hay ngồi. Sử dụng hằng số đo thực nghiệm `bakedHeadHeight = 0.263m` và dùng chiều cao người đứng (`referenceModelHeight = 1.798m`) làm quy chuẩn đồng nhất duy nhất cho toàn bộ 6 tư thế.
- **Phòng ngừa & Test**: `testEveryPoseUsesTheSameScaleFactor` kiểm tra tất cả các tư thế đều sử dụng chung một tỉ lệ co giãn duy nhất.

---

### BUG-012: Camera ngắm theo đường mắt 1/3 làm nửa dưới người bị cắt cụt
- **Phân loại**: RealityKit / Khung ngắm & Bố cục
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Bóng người bị cắt ở đáy khung"
  XCTestFailure: "Bóng người chỉ chiếm \(Int(coverage * 100))% chiều cao khung — bị cắt cụt"
  XCTAssertLessThan failed: (rows.upperBound: 640) is not less than (cgImage.height: 640)
  ```
- **Triệu chứng**: Khung hình camera bắt đầu từ độ cao $Y = 0.361\text{ m}$ trở lên, người mẫu bị mất toàn bộ cẳng chân và bàn chân.
- **Nguyên nhân gốc rễ**: Công thức đặt cao độ camera dựa trên đường mắt 1/3 mâu thuẫn với `cameraDistance` (vốn đã tính để người mẫu chiếm trọn 85% chiều cao khung hình).
- **Giải pháp**: Đặt tâm camera tại đúng vị trí trung tâm chiều cao khung nhìn: `frameCenterY = visibleHeight / 2`. Đường mắt sẽ tự động rơi vào vị trí chuẩn 1/3 mà không cần bù trừ thủ công.
- **Phòng ngừa & Test**: `testFigureFitsInsideFrame` và `testFigureFillsMostOfTheFrame` kiểm tra ảnh render thực tế, bắt buộc bóng người chiếm từ 45% đến 95% chiều cao khung hình và không bị chạm biên trên/dưới.

---

### BUG-013: `PhysicallyBasedMaterial` mặc định `.opaque` bỏ qua alpha màu
- **Phân loại**: RealityKit / Shading & Materials
- **Mức độ**: Trung bình
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Vật liệu đang để `.opaque` — alpha trong `baseColor` bị bỏ qua, người 3D hiện thành khối đặc chứ không mờ."
  RealityKit Check: PhysicallyBasedMaterial.blending != .transparent
  ```
- **Triệu chứng**: Người 3D hiển thị dạng một khối đặc có màu nhạt, che khuất toàn bộ cảnh và người mẫu thực tế phía sau thay vì tạo bóng mờ bán trong suốt.
- **Nguyên nhân gốc rễ**: `PhysicallyBasedMaterial` mặc định thuộc tính `blending` là `.opaque`. Khi ở chế độ này, kênh Alpha trong `baseColor.tint` hoàn toàn bị RealityKit phớt lờ.
- **Giải pháp**: Cấu hình chế độ hoà trộn tường minh:
  ```swift
  material.blending = .transparent(opacity: .init(scale: alpha))
  ```
- **Phòng ngừa & Test**: `testMaterialIsActuallyTransparent` xác nhận thuộc tính `material.blending` thuộc enum case `.transparent`.

---

### BUG-014: Cảnh thiếu ánh sáng đa chiều làm bóng 3D phẳng lì như ảnh dán
- **Phân loại**: RealityKit / Lighting Setup
- **Mức độ**: Trung bình
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Ảnh chụp gần như chỉ có một màu — cảnh nhiều khả năng không dựng được"
  XCTAssertGreaterThan failed: (distinct pixel colors: 12) is not greater than (50)
  ```
- **Triệu chứng**: Mô hình không có bóng khối, không cảm nhận được chiều sâu không gian, trông giống một tấm hình 2D dán đè lên màn hình.
- **Nguyên nhân gốc rễ**: Vật liệu PBR cần tương tác ánh sáng phản xạ để tạo khối. Nếu không có nguồn sáng thích hợp, các bề mặt đều nhận mức sáng đồng đều hoặc tối sầm.
- **Giải pháp**: Thêm `SceneLighting` gồm nguồn sáng chính chiếu góc và nguồn sáng phụ khuếch tán đa chiều.
- **Phòng ngừa & Test**: `TranslucentSceneView.makeTestLights` cung cấp endpoint cho unit test kiểm tra số lượng và cường độ các nguồn sáng trong cảnh.

---

### BUG-015: `RealityView` (iOS 18+) bỏ qua `PerspectiveCamera` tạo thủ công
- **Phân loại**: iOS 18 API / RealityView Architecture
- **Mức độ**: Nghiêm trọng (Lỗi im lặng)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Camera ảo không nhìn thấy người — nhánh RealityView hỏng"
  XCTestFailure: "Người chỉ chiếm \(Int(coverage * 100))% chiều cao khung — camera ảo đứng sai chỗ"
  Log warning: [RealityKit] PerspectiveCamera entity attached to AnchorEntity is not supported by RealityView CameraMode.virtual.
  ```
- **Triệu chứng**: Trên iOS 18+, người mẫu 3D bị cắt cụt và lệch góc nhìn, trong khi trên iOS 17 (`ARView`) hoàn toàn bình thường; các unit test cũ đều báo xanh vì chỉ test trên `ARView`.
- **Nguyên nhân gốc rễ**: `RealityView` trên SwiftUI không sử dụng camera entity do người dùng thêm vào anchor (chỉ hỗ trợ camera hệ thống `.virtual` hoặc `.spatialTracking`). Vì vậy, camera tuỳ biến bị bỏ qua hoàn toàn.
- **Giải pháp**: Phân nhánh xử lý: trên iOS 18, không đặt vị trí camera mà tạo một entity mục tiêu rỗng `GuideCamera.target` để camera hệ thống tự ngắm vào (`cameraTarget`).
- **Phòng ngừa & Test**: Viết unit test riêng `testRealityViewBranchFramesTheFigure` dựng cảnh bằng virtual camera tương tự nhánh iOS 18 và chụp ảnh snapshot để kiểm tra độ bao phủ khung hình.

---

### BUG-016: Đọc `@Published` từ background queue gây Crash Runtime (Concurrency)
- **Phân loại**: Swift Concurrency / Thread Safety
- **Mức độ**: Nghiêm trọng (Crash App)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  Fatal error: Incorrect actor executor assumption: Expected MainActor, but executing on com.apple.root.default-qos / analysisQueue
  Thread 5: EXC_BREAKPOINT (code=1, subcode=0x1a2b3c4d) in MainActor.assumeIsolated<T>(_:)
  ```
- **Triệu chứng**: Ứng dụng crash ngay lập tức khi camera vừa khởi động và chuyển frame hình ảnh đầu tiên cho `FrameAnalyzer`.
- **Nguyên nhân gốc rễ**: Analyzer chạy trên hàng đợi nền `analysisQueue` nhưng cố gắng đọc thuộc tính UI `@Published var mode` thông qua `MainActor.assumeIsolated`. Trong chế độ Swift Strict Concurrency, thao tác này vi phạm biệt lập actor và kích hoạt fatal error lúc runtime.
- **Giải pháp**: Thiết kế `AnalysisConfigurationStore` độc lập, sử dụng khoá luồng (lock / synchronized access) để lưu bản snapshot cấu hình, cho phép background queue đọc an toàn bất kỳ lúc nào.
- **Phòng ngừa & Test**: Bộ test `AnalysisConfigurationTests` thực hiện `concurrentPerform` với 500 vòng lặp đồng thời ghi và đọc để đảm bảo không mất dữ liệu hay xung đột luồng.

---

### BUG-017: Rung lắc máy ảnh khi zoom xa và giật khựng khi đổi tư thế
- **Phân loại**: AVFoundation / Camera Hardware Control
- **Mức độ**: Trung bình
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  NSGenericException: *** -[AVCaptureDevice lockForConfiguration:] must be called before modifying videoZoomFactor
  AVFoundation Log: Device ramp interrupted or unsmoothed focus jitter observed during active capture session
  ```
- **Triệu chứng**: Ở mức zoom cao, rung tay bị khuếch đại làm ảnh mờ nhoè; khi app tự đổi mức zoom theo tư thế, màn hình bị giật mạnh.
- **Nguyên nhân gốc rễ**: Thay đổi `videoZoomFactor` đột ngột không qua làm mượt, thiếu bật tính năng chống rung và tự động lấy nét liên tục của phần cứng.
- **Giải pháp**: Trong `CameraService.setZoom`: khoá cấu hình `device.lockForConfiguration()`, bật `smoothAutoFocusEnabled`, `continuousAutoFocus`, `continuousAutoExposure`. Khi app tự động zoom thì nhảy thẳng (không animated để tránh trễ), khi người dùng zoom thủ công thì dùng `device.ramp(toVideoZoomFactor:withRate: 4)`.
- **Phòng ngừa & Test**: Đo đạc độ ổn định khung hình trong `AutoCaptureTests`.

---

### BUG-018: Quá nhiều thông báo chỉ dẫn kỹ thuật làm che khuất khung ngắm
- **Phân loại**: UX / Overlay Guidance
- **Mức độ**: Thấp
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Lời nhắc phải chứa động từ hành động, không chỉ nêu lại lỗi."
  XCTestFailure: "Sai nhỏ thì không được bắt lỗi — sẽ phiền"
  UI Defect: Overlapping multiple coaching labels at top safe area (Viewfinder occlusion)
  ```
- **Triệu chứng**: Màn hình hiện danh sách 2–3 lỗi kỹ thuật kèm số liệu (ví dụ: "Khoảng cách 2.1m, góc nghiêng 12 độ, thiếu sáng"), đặt ở đỉnh khung che mất đầu người mẫu và gây bối rối cho người chụp.
- **Nguyên nhân gốc rễ**: Thuật toán gom tất cả các điều kiện vi phạm thành một mảng và hiển thị đồng thời mà không xếp hạng mức độ ưu tiên.
- **Giải pháp**: Thiết kế thuật toán ưu tiên trong `QualityCoachOverlay`: chỉ chọn ra **đúng 1 lỗi cấp thiết nhất** tại một thời điểm (Ưu tiên: Ánh sáng -> Khoảng cách -> Góc máy -> Căn chỉnh tư thế). Nội dung nhắc nhở bắt đầu bằng động từ hành động ngắn gọn (ví dụ: "Tiến lại gần", "Di chuyển ra nơi sáng hơn").
- **Phòng ngừa & Test**: `CoachingMessageTests` kiểm tra thông điệp luôn chứa động từ hành động và không bao giờ vượt quá 1 thông điệp cùng lúc.

---

### BUG-019: Trộn lẫn trục toạ độ khi tính tỉ lệ cắt ảnh camera (`SafeArea`)
- **Phân loại**: Math / Computer Vision Coordinates
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Chiều cao đầu phải theo chiều cao khung"
  XCTAssertEqual failed: Trộn hai trục toạ độ làm sai lệch bố cục ~30%
  Assertion Check: layout.headHeightRatio != pose.headHeightRatio
  ```
- **Triệu chứng**: Tỉ lệ khớp tư thế bị sai lệch khoảng 30% giữa trục ngang và trục dọc khi camera hiển thị ở chế độ lấp đầy màn hình (`resizeAspectFill`).
- **Nguyên nhân gốc rễ**: Khung hình camera và khung hiển thị SwiftUI có tỉ lệ khung hình (aspect ratio) khác nhau (3:4 vs màn hình điện thoại 19.5:9). Việc chuẩn hoá bề rộng theo chiều cao khung hình hoặc ngược lại làm biến dạng hệ toạ độ chuẩn hoá $[0, 1]$.
- **Giải pháp**: Tách biệt rõ ràng việc chuẩn hoá: bề ngang thân người tính theo chiều ngang khung hình, chiều cao tính theo chiều cao khung hình trong `SafeArea` và `SceneComposer`.
- **Phòng ngừa & Test**: `SafeAreaTests` kiểm tra các trường hợp cắt ngang (narrow view in wide buffer) và cắt dọc (wide view in tall buffer); `SceneComposerTests.testWidthAndHeightUseDifferentAxes` chặn lỗi trộn trục.

---

### BUG-020: AutoCapture bấm chụp khi người mẫu chưa ổn định hoặc đang chớp mắt
- **Phân loại**: Logic / Auto-Trigger Decider
- **Mức độ**: Trung bình
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Chưa đủ 1,2 giây thì chưa bấm"
  XCTestFailure: "Thời gian giữ yên là đánh đổi cân bằng, không đổi tuỳ ý"
  XCTAssertNotEqual failed: ("capture") is equal to ("capture") at t = 1.0s
  ```
- **Triệu chứng**: Ảnh tự động chụp ra bị nhoè mờ do người mẫu vừa bước vào khung chưa kịp đứng yên, hoặc chụp đúng khoảnh khắc người mẫu nhắm mắt.
- **Nguyên nhân gốc rễ**: Bộ kích hoạt tự động chụp chỉ kiểm tra điều kiện tại một thời điểm tức thời (instant frame check) mà không có cửa sổ giữ yên (stillness window).
- **Giải pháp**: Thiết lập thuật toán `AutoCaptureDecider` yêu cầu đồng thời 3 điều kiện được duy trì liên tục trong suốt **1.2 giây**:
  1. Tư thế đã khớp (`isAligned == true`)
  2. Người mẫu giữ yên không dao động đầu (`headMoved == false`)
  3. Cả hai mắt đang mở (`eyesOpen == true`)
- **Phòng ngừa & Test**: `AutoCaptureTests.testStillnessWindowIsPointTwoSeconds` ghim cố định mốc thời gian 1.2s; `testDoesNotCaptureBeforeStillnessWindow` xác nhận không bấm chụp trước khi đủ thời gian.

---

### BUG-021: Khối bàn ghế hộp (`FurnitureBuilder`) đặt ngược chiều `+Z` chắn trước mặt người mẫu
- **Phân loại**: RealityKit / Scene Composition
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Cảnh hướng dẫn của `seated-straight` chỉ được chứa đúng 1 mesh người mẫu, không được gắn thêm khối bàn ghế hộp gây chắn tầm nhìn (thấy 4 mesh)"
  Visual Defect: Chair backRest (z = +0.78m) and table top (z = +0.35m) placed between camera (z = +1.73m) and character (z = 0), occluding upper body with stacked alpha rectangles.
  ```
- **Triệu chứng**: Ở các tư thế ngồi (`seated-straight`, `seated-chin`, `seated-lean`), trên màn hình xuất hiện các dải hình chữ nhật lớn dọc và ngang đè прямо lên ngực, đầu và đầu gối của người mẫu 3D, làm rối khung ngắm camera.
- **Nguyên nhân gốc rễ**: Camera đặt ở phía `+Z` nhìn về `0`. Tuy nhiên `FurnitureBuilder.makeTable` lại cộng dương trục Z cho mặt ghế (`z = +0.58m`) và lưng ghế (`z = +0.78m`) khi gắn vào `furniture` tại `z = +0.35m`, khiến chiếc ghế nằm ngay sát trước ống kính camera và chắn trước mặt nhân vật.
- **Giải pháp**: Loại bỏ hoàn toàn khối bàn ghế hộp khỏi `GuideSceneBuilder.build(pose:metrics:)`, chỉ hiển thị duy nhất mô hình người mẫu 3D sạch sẽ trên khung ngắm.
- **Phòng ngừa & Test**: `FigureAssetTests.testGuideSceneDoesNotIncludeFurnitureBoxes` kiểm tra `GuideSceneBuilder.build` cho mọi tư thế chỉ chứa đúng 1 mesh người mẫu duy nhất.

---

### BUG-022: `RealityView` nhìn vào gốc `(0,0,0)` đẩy người lên nửa trên, kẹt màu xanh lá và không đổi tư thế
- **Phân loại**: RealityKit / View & State Management
- **Mức độ**: Nghiêm trọng (Lỗi im lặng)
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Khi chưa có dữ liệu người thật trong khung (`CaptureMeasurements()`), `isAligned` phải là `false` (màu cam hướng dẫn), không được báo xanh lá"
  Visual Defect: RealityView .virtual camera looks at world origin (0, 0, 0), placing feet (Y = 0) at vertical screen center and freezing initial material/pose due to missing update closure.
  ```
- **Triệu chứng**:
  1. Hai bàn chân người 3D (`Y = 0`) nằm lơ lửng ngay chính giữa màn hình, toàn bộ thân người bị dồn lên nửa trên khung ngắm và cắt sát đỉnh đầu.
  2. Khi mở máy chưa có người trong khung, người 3D lại hiện màu **xanh lá** (đã khớp) thay vì màu cam hướng dẫn, và khi bấm chọn tư thế khác trên thanh `poseStrip` thì hình 3D đứng im không đổi dáng.
- **Nguyên nhân gốc rễ**:
  1. `CameraView.match` trả về `PostureMatch(adjustment: .none, ...)` khi `camera.latestAnalysis == nil`, làm `match.isAligned` mang giá trị `true` ở frame khởi tạo đầu tiên.
  2. Nhánh `RealityView` không có closure `update` và gán `content.cameraTarget` bằng một entity rỗng chưa gắn vào cây cảnh, khiến camera `.virtual` mặc định nhìn thẳng vào gốc `(0, 0, 0)` và không bao giờ cập nhật lại màu hay tư thế sau frame đầu tiên.
- **Giải pháp**:
  1. Sửa `CameraView.match` truyền `CaptureMeasurements()` rỗng vào `PostureMatch.evaluate` khi `latestAnalysis == nil` để `isAligned` luôn là `false` khi chưa có người.
  2. Hợp nhất `TranslucentSceneView` dùng `ARView` ở chế độ `.nonAR` (`automaticallyConfigureSession: false`) với `PerspectiveCamera` tường minh tại `GuideCamera.position(for: pose)` và cập nhật đầy đủ cả tư thế lẫn vật liệu trong `updateUIView`.
- **Phòng ngừa & Test**: `FigureAssetTests.testEmptyMeasurementsAreNotAligned` chặn lỗi trả về `isAligned == true` khi chưa nhận diện được người; `FigureRenderTests` xác nhận khung hình render đầy đủ.

---

### BUG-023: Mesh `Beta_Surface` bị hở cổ, rỗng toàn bộ vùng bụng/eo và lộ vách ngăn nội bộ như người máy
- **Phân loại**: Asset 3D / RealityKit Material
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  Visual Defect: Beta_Surface consists of 15 disconnected body shells with a 13cm gap at the waist/abdomen (Z = 1.00..1.31), missing neck, missing joint sleeves, and 3,143 internal end-cap faces (including 32-triangle and 28-triangle pole fans in Hips) visible through translucent material.
  ```
- **Triệu chứng**: Người mẫu 3D trên màn hình bị đứt lìa đầu khỏi vai (không có cổ), rỗng hoàn toàn vùng bụng/eo giữa ngực và chậu, hở các khớp vai/khuỷu/gối/cổ chân, đồng thời bên trong vùng chậu và các đầu khớp hiện rõ các đường nan quạt và vách ngăn ngang giống búp bê robot tháo khớp.
- **Nguyên nhân gốc rễ**:
  1. Model `Beta` của Mixamo chia cơ thể thành các mảnh vỏ rời (`Beta_Surface`) nối bằng các khối cầu khớp (`Beta_Joints`). Khi xóa `Beta_Joints` ở `BUG-006`, các khoảng trống ở cổ, bụng/eo và khớp bị bỏ trống hoàn toàn.
  2. Mỗi mảnh vỏ trong `Beta_Surface` lại được bịt kín ở hai đầu bằng các mặt nắp nội bộ (internal end-caps), kết hợp với `alphaWhenGuiding = 0.30` và không bật `faceCulling = .back`, khiến RealityKit vẽ xuyên thấu cả mặt trước, vách ngăn nội bộ lẫn mặt lưng.
- **Giải pháp**:
  1. Viết script `tools/skin_poses.py` tự động cắt bỏ toàn bộ 3.143 mặt nắp nội bộ tại 28 đầu khớp và khâu kín (watertight 2-manifold) 14 ống da giải phẫu đa tầng (Hermite bậc 3 + làm mượt bảo toàn thể tích Taubin $\lambda|\mu$) nối liền Đầu – Cổ – Ngực – Bụng/Eo – Hông – Đùi – Gối – Bắp chân – Cổ chân – Bàn chân và Vai – Tay trên cả 6 file `pose-*.usdz`.
  2. Cập nhật `FigureMaterial` sang tông màu da người ấm áp (`alphaWhenGuiding = 0.65`, `roughness = 0.52`, `clearcoat = 0.15`) và bật `material.faceCulling = .back`.
- **Phòng ngừa & Test**: `FigureAssetTests.testFigureMaterialUsesBackFaceCullingAndHumanSkinTone` kiểm tra `faceCulling == .back` và độ đục lớp da; `tools/skin_poses.py` kiểm định `verify_manifold` (mọi cạnh đều có bậc vô hướng = 2, bậc có hướng = 1) cho cả 6 file `.usdz`.

---

### BUG-024: Người mẫu 3D bị gắn cứng vào khung màn hình 2D thay vì đứng trong không gian thực
- **Phân loại**: RealityKit / Camera & CoreMotion
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Camera 3D phải xoay theo góc nghiêng/lia thực tế của iPhone để neo người mẫu trong không gian thực"
  Visual Defect: PerspectiveCamera in .nonAR mode had static position and identity orientation, causing the 3D figure to move rigidly with the 2D screen like a flat sticker when tilting, panning, or zooming the phone.
  ```
- **Triệu chứng**: Khi người chụp nghiêng máy lên/xuống, xoay ngang tìm góc hoặc zoom camera, người mẫu 3D trôi cứng ngắc theo khung viền màn hình điện thoại thay vì đứng vững trên mặt sàn trong không gian thực.
- **Nguyên nhân gốc rễ**: `ARView` chạy ở chế độ `.nonAR` (để không xung đột với `AVCaptureSession` của `CameraService`), nhưng `PerspectiveCamera` chỉ được gán vị trí tĩnh một lần duy nhất và không cập nhật góc quay/vị trí/FOV theo cảm biến chuyển động của thiết bị hay mức zoom của camera.
- **Giải pháp**: Bổ sung `GuideCamera.spatialState(for:pitch:yaw:roll:translationOffset:zoomFactor:)` và tích hợp `CMMotionManager` (60 Hz) trong `TranslucentARViewRepresentable.Coordinator` để tính pitch/roll từ vector trọng lực trái đất $\vec{g}$, tích phân yaw quanh trục thẳng đứng $-\vec{g}$, dịch chuyển thị sai 3D (parallax) và đồng bộ FOV theo `camera.zoomFactor`.
- **Phòng ngừa & Test**: `FigureAssetTests.testSpatialCameraReactsToTiltPanAndZoom` kiểm chứng `GuideCamera.spatialState` phản hồi đúng cả góc quay 3D, dịch chuyển vị trí và thu hẹp FOV khi zoom.

---

### BUG-025: Người mẫu 3D bay lơ lửng giữa không trung vì thiếu nhận diện mặt sàn thực (`ARWorldTrackingConfiguration`) và thiếu bóng đổ sàn
- **Phân loại**: ARKit / RealityKit / Camera
- **Mức độ**: Nghiêm trọng
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Chân người mẫu (gốc Y=0 của anchor) phải ghim chính xác xuống cao độ mặt sàn `floorY`"
  Visual Defect: Without ARWorldTrackingConfiguration horizontal plane raycasting and planar ground shadows, the 3D figure appears to float in mid-air without a locked 6-DoF floor anchor point on the real floor tiles.
  ```
- **Triệu chứng**: Dù camera đã xoay theo con quay hồi chuyển (`CMMotionManager`), người mẫu 3D vẫn có cảm giác bay lơ lửng giữa không trung, không có điểm neo (anchor) đinh ghim cố định vào một viên gạch cụ thể trên mặt sàn thực như các filter AR World của TikTok, và dưới chân không có bóng đổ trải trên sàn nhà.
- **Nguyên nhân gốc rễ**:
  1. Con quay hồi chuyển (`CMMotionManager`) chỉ đo được 3 bậc tự do góc quay (3-DoF rotation), hoàn toàn không biết cao độ thực tế của mặt sàn (`floorY`) hay vị trí dịch chuyển 6-DoF của điện thoại trong phòng, đồng thời lớp `ARView` `.nonAR` tách rời khỏi `AVCaptureVideoPreviewLayer` nên không khớp ma trận nội tại (camera intrinsics) của ống kính thật.
  2. Thiếu mặt phẳng bắt bóng (`OcclusionMaterial(receivesDynamicLighting: true)`) và bóng đổ silhouette cơ thể trải trên mặt sàn (`Y = 0`) ngay dưới gót chân.
- **Giải pháp**:
  1. Trên thiết bị iPhone thực (`GuideCamera.supportsRealSpaceAR`), khởi chạy `ARView` ở chế độ `.ar` với `ARWorldTrackingConfiguration(planeDetection: [.horizontal])` và `environmentTexturing = .automatic`.
  2. Xây dựng cầu nối `CameraService.setExternalARActive(true)` + `ingestARPixelBuffer(_:)`: khi `ARSession` chạy, `CameraService` tạm dừng `AVCaptureSession` riêng (tránh xung đột phần cứng camera), nhận trực tiếp `ARFrame.capturedImage` để phân tích dáng người qua Vision và chụp ảnh gốc sạch (không dính mẫu 3D) qua `capturePhoto(with:)`.
  3. Dùng raycast mặt phẳng ngang (`makeRaycastQuery(allowing: .existingPlaneGeometry / .existingPlaneInfinite / .estimatedPlane, alignment: .horizontal)`) kết hợp `ARPlaneAnchor` thấp nhất để ghim cứng `AnchorEntity` xuống đúng mặt sàn tại `Y = floorY` (`GuideCamera.floorAnchorTransform`), hỗ trợ chạm vào sàn để đổi vị trí neo.
  4. Bổ sung `GroundShadowBuilder.makeFloorShadow(for:)` tạo đồng thời mặt phẳng `OcclusionMaterial(receivesDynamicLighting: true)`, bóng tiếp xúc dưới đế giày (`floor-contact-shadow`), và bóng đổ hình chiếu cơ thể trải dài trên mặt sàn (`floor-projected-silhouette`) kèm `DirectionalLightComponent.Shadow`.
- **Phòng ngừa & Test**: `FigureAssetTests.testFloorAnchorTransformPinsFeetToDetectedFloorY` và `FigureAssetTests.testGroundShadowBuilderCreatesFloorShadowAtGroundLevel`.

---

### BUG-026: Fallback mặt phẳng ảo (`camY - 1.20`) làm mẫu 3D trôi theo ống kính khi chưa quét xong sàn, thiếu `ARTrackedRaycast`, thiếu `ARCoachingOverlayView` và huỷ `ARSession` khi ẩn/hiện mẫu
- **Phân loại**: ARKit / RealityKit / Anchoring & UX
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Phải từ chối điểm raycast nằm quá cao gần tầm ống kính (tránh đặt mẫu lên mặt bàn cao/tường)"
  Visual Defect: Hardcoded fallbackFloorY = camY - 1.20 with hitPosition = nil places the 3D figure on a synthetic camera-relative plane before horizontal plane detection completes, causing the model to float and drift with camera movement; toggling overlayVisible destroys ARView and resets ARSession.
  ```
- **Triệu chứng**:
  1. Trong những giây đầu khi ARKit chưa nhận diện xong mặt sàn (hoặc khi người dùng lia máy ở nơi thiếu sáng/ít vân), mẫu 3D bị đặt trên mặt phẳng ảo tự dựng `fallbackFloorY = camY - 1.20` cách camera một khoảng cố định `targetDistance` nên bị trôi lơ lửng theo chuyển động ống kính.
  2. Ở bước kiểm tra `detectedFloorY`, việc gọi `placeAndLockAnchor(..., hitPosition: nil, lock: true)` làm khoá cứng mẫu vào toạ độ suy diễn từ vector nhìn của camera thay vì toạ độ giao cắt `ARRaycastResult.worldTransform` thực tế trên mặt đất, và không dùng `ARTrackedRaycast` để bám theo mặt phẳng khi ARKit tinh chỉnh bản đồ phòng.
  3. Chưa tích hợp `ARCoachingOverlayView(goal: .horizontalPlane)` để hướng dẫn người dùng quét sàn, đồng thời chưa đồng bộ `ARLightEstimate.ambientIntensity` vào hệ thống đèn và thiếu `sceneUnderstanding.options.insert(.receivesLighting)`.
  4. Trong `CameraView`, nhánh `if overlayVisible { templateOverlay }` tháo hoàn toàn `ARView` khỏi cây giao diện khi người dùng bấm nút ẩn/hiện mẫu, làm `ARSession` bị dừng và mất điểm neo sàn.
- **Nguyên nhân gốc rễ**:
  1. Tư duy "luôn vẽ mẫu 3D ở frame đầu bằng mọi giá" dẫn tới việc bịa ra toạ độ `camY - 1.20` trong không gian camera khi chưa có kết quả raycast mặt phẳng thật.
  2. Chưa lọc phân loại mặt phẳng (`ARPlaneAnchor.Classification` như `.ceiling`, `.table`, `.seat`) và chưa kiểm tra độ sụt cao độ tối thiểu (`shouldAcceptFloorRaycastHit`), đồng thời thiếu `ARTrackedRaycast` để duy trì liên kết liên tục với mặt sàn thực.
- **Giải pháp**:
  1. Loại bỏ hoàn toàn fallback mặt phẳng ảo `camY - 1.20`: bọc mẫu 3D, bóng đổ và đèn trong `rigContainer` (`guide-rig-container`) với `isEnabled = false` khi mới khởi tạo AR, chỉ bật `isEnabled = true` ngay khi `ARRaycastQuery` bắt trúng mặt phẳng ngang hợp lệ (`shouldAcceptFloorRaycastHit`).
  2. Tích hợp `ARTrackedRaycast` (`session.trackedRaycast(_:updateHandler:)`) để liên tục tinh chỉnh cao độ mặt sàn theo thời gian thực, lọc bỏ các `ARPlaneAnchor` thuộc trần/bàn/ghế, và bật `sceneReconstruction = .meshWithClassification` trên thiết bị có LiDAR.
  3. Tích hợp `ARCoachingOverlayView` (`goal = .horizontalPlane`, `activatesAutomatically = true`) vào `ARView` để hướng dẫn người dùng quét mặt đất tự nhiên, đồng thời giữ `TranslucentSceneView` sống xuyên suốt khi bấm nút ẩn/hiện overlay thông qua thuộc tính `isTemplateVisible`.
  4. Đồng bộ cường độ ánh sáng môi trường thực (`ARLightEstimate.ambientIntensity`) qua `GuideCamera.ambientLightFactor` và `SceneLighting.updateIntensity`.
- **Phòng ngừa & Test**: `FigureAssetTests.testShouldAcceptFloorRaycastHitRejectsElevatedOrOutOfRangeHits` và `FigureAssetTests.testAmbientLightFactorScalesAndClampsSceneLighting`.

---

### BUG-027: Mesh chữ nhật màu xám nhân tạo (`floor-contact-shadow` & `floor-projected-silhouette`) dưới chân mẫu, thiếu thuật toán chọn góc đứng 1/3 + Lerp/Slerp, và khung ngắm UI bị co cụm 3:4 kèm popup lỗi trên Simulator
- **Phân loại**: RealityKit / Shadow & Pro Camera UI/UX
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  XCTestFailure: "Phải xóa bỏ hoàn toàn mesh chữ nhật màu xám nhân tạo dưới chân mẫu"
  Visual Defect: GroundShadowBuilder attached an UnlitMaterial gray rectangular plane (floor-contact-shadow) and a flattened silhouette clone (floor-projected-silhouette) under the feet; CameraView constrained the viewfinder to a boxed 3:4 frame with opaque controls and showed a blocking "Camera gặp sự cố" popup on Simulator.
  ```
- **Triệu chứng**:
  1. Dưới bàn chân mẫu 3D xuất hiện một tấm hình chữ nhật màu xám nhân tạo và bóng đổ giả lập thay vì bóng đổ thật hoà vào mặt đất.
  2. Mẫu 3D chỉ bắn 1 tia raycast cố định và gán thẳng toạ độ làm mẫu nhảy vị trí đột ngột (teleport) mà chưa tự tìm vị trí tối ưu theo bố cục 1/3 (Rule of Thirds) trong khoảng cách vàng `1.8m – 2.5m` hay làm mượt bằng `simd_mix` / `simd_slerp`.
  3. Giao diện `CameraView` đóng khung `aspectRatio(3/4)` nhỏ ở giữa màn hình, dùng `Picker` segmented mặc định và các nút màu đục; khi chạy trên Simulator lại hiện popup lỗi `"Camera gặp sự cố - Thiết bị này không có camera phù hợp"` đè lên giữa mẫu 3D.
- **Nguyên nhân gốc rễ**:
  1. `GroundShadowBuilder` tạo thêm `contactDisk` (`MeshResource.generatePlane` với `UnlitMaterial(white: 0, alpha: 0.24)`) và `flattener` (`UnlitMaterial(white: 0, alpha: 0.30)`), đồng thời gắn cả trong chế độ `.nonAR` khiến chúng hiện lên như một tấm thảm chữ nhật màu xám dưới chân.
  2. Thiếu thuật toán đánh giá ứng viên mặt sàn theo lưới 1/3 (`ruleOfThirdsRaycastPoints`, `scoreFloorCandidate`) và thiếu bộ nội suy `SceneEvents.Update` (`simd_mix` + `simd_slerp`).
  3. `CameraView` xếp `VStack` tuần tự thay vì `ZStack` tràn viền (Full-bleed Viewfinder), và `CameraService.start()` trên Simulator cố tìm `AVCaptureDevice` phần cứng rồi báo lỗi.
- **Giải pháp**:
  1. Xoá hoàn toàn `floor-contact-shadow` và `floor-projected-silhouette` khỏi `GroundShadowBuilder.makeFloorShadow(for:)`, chỉ giữ duy nhất mặt phẳng vô hình `floor-shadow-catcher` (`OcclusionMaterial(receivesDynamicLighting: true)`) và chỉ gắn khi chạy AR thực tế.
  2. Bổ sung thuật toán Smart Auto-Placement trong `GuideCamera` & `Coordinator`: quét các điểm giao 1/3 (`ruleOfThirdsRaycastPoints`), chấm điểm khoảng cách vàng `1.8m – 2.5m` (`scoreFloorCandidate`, `idealStandOffDistance`), tự động xoay hướng mặt nghệ thuật về phía ống kính (`artisticLookAtOrientation`) và làm mượt 60Hz bằng `simd_mix` / `simd_slerp` (`smoothTransform`).
  3. Tái thiết kế toàn bộ `CameraView`, `GridOverlay`, `QualityCoachOverlay` theo ngôn ngữ **Pro Camera & Minimalist Glass** (Full-bleed Viewfinder tràn viền, `.ultraThinMaterial` + `strokeBorder(Color.white.opacity(0.15))`, hiệu ứng trượt `matchedGeometryEffect`, nút Shutter đôi có `UIImpactFeedbackGenerator`), đồng thời cho phép `CameraService` trên Simulator vào thẳng chế độ Studio 3D Preview không báo lỗi giả.
- **Phòng ngừa & Test**: `FigureAssetTests.testGroundShadowBuilderCreatesFloorShadowAtGroundLevel` và `FigureAssetTests.testSmartAutoPlacementHeuristicsAndSmoothing`.

---

### BUG-028: `OcclusionMaterial(receivesDynamicLighting: true)` rộng 3.6m tạo mảng xám cắt chéo sàn, mẫu 3D lệch sang rìa trái chạm thanh điều khiển trên, và iOS 26 Liquid Glass tự chèn vòng tròn nâu/viền đôi làm rối giao diện
- **Phân loại**: iOS 26 UI / RealityKit Occlusion & Framing
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  Visual Defect (Observed on iPhone Real Device running iOS 26):
  1. 3.6m x 3.6m plane with OcclusionMaterial(receivesDynamicLighting: true) + 3 DirectionalLights renders a large translucent gray slab cutting diagonally across the right side of the floor.
  2. Raycast candidate at x = 1/3 placed the 3D figure on the far left of the screen at 1.90m, causing the head to collide with the 3-row top UI stack.
  3. iOS 26 SDK default Button/Menu styling + TabView(.tint(.netCoral)) injected dark brown circular backgrounds on top toolbar buttons and double coral-tinted Liquid Glass halos around bottom pills.
  ```
- **Triệu chứng**:
  1. Góc dưới bên phải khung ngắm xuất hiện một mảng phẳng màu xám đục có cạnh cắt thẳng sắc lẹm đè lên sàn nhà và đồ vật.
  2. Mẫu 3D bị đặt lệch hẳn sang mép trái màn hình (`x ≈ 22%`) và đứng quá gần (`1.90m`) làm đỉnh đầu đâm xuyên vào cụm nút ở đỉnh màn hình.
  3. Giao diện có tới 6 tầng nút (3 hàng ở trên + 3 hàng ở dưới gồm cả `TabView`), các nút icon trên cùng bị bọc trong 4 hình tròn màu nâu sẫm và các nút `MÀU PHIM` / `BỐ CỤC` bị bọc 2 lớp viền nâu đỏ chồng chéo.
- **Nguyên nhân gốc rễ**:
  1. Trên iOS 26, `OcclusionMaterial(receivesDynamicLighting: true)` khi kết hợp với nhiều `DirectionalLight` (`key`, `fill`, `rim`) và `DirectionalLightComponent.Shadow` sẽ tô xám toàn bộ vùng diện tích `3.6m × 3.6m` của mesh phẳng.
  2. Khi `findBestRuleOfThirdsFloorHit` lấy trực tiếp toạ độ `(hit.x, hit.z)` của tia bắn lệch sang `x = 1/3`, mẫu 3D bị đặt lệch khỏi tâm khung ngắm; đồng thời khoảng cách `1.90m` là quá gần với chiều cao `1.70m` trên tiêu cự camera dọc.
  3. Trên iOS 26 SDK, `Button` và `Menu` không gắn `.buttonStyle(.plain)` nằm trong `TabView` có `.tint(Color.netCoral)` sẽ tự động được hệ điều hành vẽ thêm lớp vỏ Liquid Glass màu nâu đỏ bao ngoài background tự tạo.
- **Giải pháp**:
  1. Chuyển `floor-shadow-catcher` sang `OcclusionMaterial()` thuần (không bật `receivesDynamicLighting`), thu gọn kích thước về đúng dưới đế giày (`0.35m × 0.35m`) và tắt shadow frustum toàn cảnh trên `key` light, xoá sạch 100% mảng xám cắt ngang sàn nhà.
  2. Trong `lockToRealFloor`: khi tự động đặt mẫu (`isUserTap == false`), ghim chính xác cao độ chân xuống mặt sàn thật (`Y = floorY`), nhưng đặt toạ độ `(X, Z)` nằm ngay trên trục chính giữa khung ngắm (`horizForward`) ở cự ly chuẩn `2.15m` (ngồi) và `2.42m` (đứng) kèm góc xoay 3/4 nhẹ (`12°`), đồng thời tự động dịch mượt khi đổi tư thế (`adjustPlacementForPoseChange`).
  3. Thu gọn giao diện từ 6 hàng xuống đúng 1 thanh mỏng ở đỉnh và 1 cụm điều khiển ở đáy: bỏ `TabView` ở `RootView` (đưa nút Bộ sưu tập về cạnh trái nút Shutter), gắn `.buttonStyle(.plain)` cho toàn bộ nút và thay `Menu` bằng nút bấm trực tiếp để triệt tiêu hoàn toàn viền nâu Liquid Glass của iOS 26.
- **Phòng ngừa & Test**: `FigureAssetTests.testGroundShadowBuilderCreatesFloorShadowAtGroundLevel` và `FigureAssetTests.testSmartAutoPlacementHeuristicsAndSmoothing`.

---

### BUG-029: `ShootingPose.frameFillRatio = 0.85` làm mẫu 3D cao chạm thanh nút trên/dưới, `isLockedToRealFloor` không tự căn lại khi lia máy, và nút Mood bị xuống dòng trên màn hình hẹp
- **Phân loại**: RealityKit Framing / AR Auto-Placement / UI Layout
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  Visual Defect (Observed on Simulator & AR Preview):
  1. ShootingPose.frameFillRatio = 0.85 (cameraDistance = 1.83m) makes the standing figure span 85% of full screen height, overlapping both topBar (y < 13%) and bottomControls/poseStrip (y > 78%).
  2. Coordinator.updateWorldFloorAnchor returned early once isLockedToRealFloor == true without checking angular drift, leaving the 3D figure behind at the screen edge when the user pans the camera.
  3. Bottom Mood pill ("Ấm áp") wrapped onto 2 lines and active pose chip ("Đứng thẳng") started half-clipped off the right edge of poseStrip.
  ```
- **Triệu chứng**:
  1. Ở tư thế đứng thẳng, đầu mẫu 3D chạm vào nút `NÉT · Chân dung` ở trên và bàn chân đè xuống dưới nút `Đứng thẳng` / nút Shutter ở đáy màn hình.
  2. Khi người dùng lia máy sang góc khác trong phòng sau khi vừa mở app, mẫu 3D bị bỏ lại ở rìa màn hình thay vì trượt êm về chính giữa góc ngắm mới.
  3. Nút `Ấm áp` bị ngắt thành 2 dòng và chip `Đứng thẳng` bị khuất một nửa ở mép phải thanh cuộn tư thế.
- **Nguyên nhân gốc rễ**:
  1. `ShootingPose.frameFillRatio = 0.85` được tính trên 100% chiều cao màn hình mà chưa trừ phần diện tích của `topBar` (~12%) và `bottomControls` (~22%), đồng thời `GuideCamera.centerHeight` đặt ở `0.90m` làm chân mẫu tụt thấp.
  2. `Coordinator.updateWorldFloorAnchor` khóa cứng `(X, Z)` ngay từ frame đầu tiên bắt được sàn mà không kiểm tra độ lệch góc nhìn (`cosAngle`) khi người dùng lia máy.
  3. Thiếu `.fixedSize(horizontal: true, vertical: false)` trên các pill ở `bottomControls` và thiếu `ScrollViewReader` tự cuộn chip tư thế đang chọn về giữa.
- **Giải pháp**:
  1. Giảm `ShootingPose.frameFillRatio` xuống `0.58` và hạ `GuideCamera.centerHeight` xuống `0.72m` (đứng) / `0.52m` (ngồi) để toàn thân mẫu 3D nằm gọn trong vùng `16%..75%` chiều cao màn hình.
  2. Trong `Coordinator.updateWorldFloorAnchor`: khi người dùng lia máy lệch `> 11°` (`cosAngle < 0.981`) hoặc đổi cự ly `> 0.35m`, tự động cập nhật mượt `targetAnchorPosition` về chính giữa góc ngắm mới trên mặt sàn thật; bổ sung cơ chế fallback sau 12 frame trên sàn gạch bóng.
  3. Bọc `poseStrip` trong `ScrollViewReader` tự cuộn tư thế đang chọn vào tâm và thêm `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)` cho các nút ở `bottomControls`.
- **Phòng ngừa & Test**: `FigureRenderTests.testFigureFillsMostOfTheFrame` và `FigureAssetTests.testSmartAutoPlacementHeuristicsAndSmoothing`.

---

### BUG-030: `lockToRealFloor` ép mẫu 3D về trục giữa ở cự ly 2.42m khiến chân mẫu đè lên mặt bàn/ly nước tiền cảnh và thân vướng quạt cây thay vì chọn khoảng sàn trống trong phòng
- **Phân loại**: AR Scene Understanding / Smart Auto-Placement
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  Visual Defect (Observed on iPhone 16 in Real Cafe Scene):
  lockToRealFloor ignored the winning raycast candidate's horizontal direction and overwrote effectiveHit with (camPos + horizForward * 2.42m), placing the 3D figure's feet at screen v = 0.82 on top of foreground glasses/coffee table and overlapping a floor fan and street motorcycles on the right, while ignoring the clean open concrete floor at (u = 0.42, v = 0.68) in front of the white curtain.
  ```
- **Triệu chứng**:
  1. Trong không gian quán cafe có bàn nước ở tiền cảnh góc dưới phải, quạt cây bên phải và khoảng sàn bê tông trống trải bên trái (trước tấm rèm trắng), mẫu 3D vẫn bị đặt cứng nhắc ở giữa-phải với bàn chân đè lên ly nước trên bàn tiền cảnh (`v ≈ 0.82`) và thân đè lên quạt cây.
  2. Chạm trực tiếp vào khoảng sàn trống trên màn hình chưa di chuyển mẫu 3D tới vị trí chạm.
- **Nguyên nhân gốc rễ**:
  1. `lockToRealFloor` khi `isUserTap == false` đã bỏ qua toạ độ `hitPosition` của điểm ứng viên và gán cứng `effectiveHit = camPos + horizForward * idealDist` (`2.42m`), đồng thời `findBestRuleOfThirdsFloorHit` chưa phân tích thị giác (`CVPixelBuffer` luma/edge/glare) và đám mây điểm 3D (`ARFrame.rawFeaturePoints`) để tránh vật cản tiền cảnh/quạt cây.
  2. `SpatialTapGesture` trong `CameraView` chỉ gọi `camera.focus(atLayerPoint:)` mà chưa gọi `camera.requestFloorAnchor(at:)`.
- **Giải pháp**:
  1. Xây dựng bộ phân tích bối cảnh thông minh 15 điểm (`GuideCamera.compositionCandidateNormalizedPoints`, `evaluateVisualSpotQuality`, `pointCloudObstaclePenalty`): chấm điểm từng vị trí trên dải sàn mở (`u ∈ 0.36...0.64, v ∈ 0.65...0.72`) theo 4 tiêu chí thị giác (sàn phẳng trống `floorOpenness`, không vướng bàn/ly nước tiền cảnh `foregroundClearance`, không vướng quạt/ghế thấp `midBodyClearance`, hậu cảnh dịu sạch không chói `backgroundHarmony`) kết hợp lọc vật cản 3D từ `rawFeaturePoints`.
  2. Trong `lockToRealFloor`: giữ nguyên hướng tia của điểm ứng viên thắng cuộc (`hitPosition`) ở cự ly phối cảnh thực tế (`2.55m – 3.65m` cho dáng đứng) để chân mẫu đậu đúng trên khoảng sàn trống (`v ≈ 0.65..0.72`), hoàn toàn tách khỏi bàn tiền cảnh.
  3. Cho phép chạm trực tiếp lên sàn trong `CameraView` để đặt mẫu (Tap-to-Place) hoặc bấm nút **Góc đẹp (`sparkles`)** để máy tự quét lại góc đứng đẹp nhất trong khung.
- **Phòng ngừa & Test**: `FigureAssetTests.testSceneAwareSmartSpotSelectionPrefersOpenFloorOverClutteredForeground`.

---

### BUG-031: Rà soát đóng gói App Store (Missing `PrivacyInfo.xcprivacy` `CA92.1`, Silent Photo Library Denied Fallback, Background AR/Camera Lifecycle, 3D Entity RAM Release & Flip Camera in AR Mode)
- **Phân loại**: App Store Compliance / Privacy / Memory & Lifecycle / UI
- **Mức độ**: Cao
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  App Store Review Audit Findings (Guidelines 2.1, 4.0, 5.1.1 & ITMS-91053):
  1. Missing PrivacyInfo.xcprivacy declaring NSPrivacyAccessedAPICategoryUserDefaults (CA92.1) for UserDefaults.standard usage in UserSettings.swift.
  2. Missing ITSAppUsesNonExemptEncryption = false in Info.plist build settings, and Marketing Version set to 1.0 instead of 1.0.0.
  3. CameraService.saveToLibrary(_:) silently ignored .denied / .restricted PHAuthorizationStatus without presenting a fallback view to open Settings.
  4. ARSession and AVCaptureSession did not pause/resume automatically across scenePhase (.background <-> .active), and Flip Camera (.front) conflicted with rear-only ARWorldTrackingConfiguration.
  5. Switching 3D poses called removeFromParent() without recursively stripping ModelComponent/animations from child entities.
  ```
- **Triệu chứng**:
  1. Khi chuẩn bị Archive lên App Store Connect, thiếu file `PrivacyInfo.xcprivacy` khai báo Required Reason API `CA92.1` cho `UserDefaults` sẽ dẫn tới cảnh báo/từ chối `ITMS-91053`, và thiếu `ITSAppUsesNonExemptEncryption = NO` làm phát sinh bước kê khai mã hóa xuất khẩu thủ công.
  2. Khi người dùng từ chối quyền Thư viện ảnh (`PHPhotoLibrary`), việc chụp ảnh không lưu được vào máy nhưng không hiển thị thông báo hướng dẫn mở Cài đặt.
  3. Khi chuyển sang camera trước (`.front`) trên thiết bị thực đang chạy `ARWorldTrackingConfiguration`, phiên AR sau không tự chuyển sang chế độ `.nonAR` cho camera trước; khi ẩn app xuống `.background`, phiên AR/Camera và đèn Torch chưa tự động tạm dừng.
  4. Khi đổi liên tục qua nhiều tư thế 3D USDZ, `removeFromParent()` đơn thuần chưa giải phóng ngay `ModelComponent` của các nút con.
- **Nguyên nhân gốc rễ**:
  1. Dự án dùng `GENERATE_INFOPLIST_FILE = YES` nhưng chưa thêm `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, chưa cập nhật chuỗi mô tả quyền chi tiết theo chuẩn Guideline 5.1.1 và chưa tạo `NET_ver1/PrivacyInfo.xcprivacy`.
  2. `CameraService.saveToLibrary(_:)` chỉ `guard status == .authorized || status == .limited else { return }` mà không phát cờ `@Published var isPhotoLibraryAccessDenied = true` lên tầng giao diện.
  3. `TranslucentSceneView` chưa theo dõi `scenePhase` và `cameraService.position`, cũng như chưa có hàm đệ quy `GuideSceneBuilder.releaseEntityHierarchy(_:)` để gỡ sạch `ModelComponent` trước khi nạp tư thế mới.
- **Giải pháp**:
  1. Cập nhật `project.pbxproj` với `INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`, `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, `MARKETING_VERSION = 1.0.0` và tạo `NET_ver1/PrivacyInfo.xcprivacy` khai báo `NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes = []`, `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`).
  2. Bổ sung `photoLibraryDeniedOverlay` trong `CameraView` và cập nhật `blockingOverlay` + `GalleryView.permissionView` dùng `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`.
  3. Quản lý vòng đời theo `scenePhase` (`pauseForBackground()`, `refreshAuthorizationAndResume()`, `Coordinator.setAppActive(_:in:)`), tự động chuyển giữa `.ar` (camera sau) và `.nonAR` (camera trước) khi lật camera, ẩn nút Flash khi camera không hỗ trợ đèn flash, tắt toàn bộ `view.debugOptions = []`, và thêm `GuideSceneBuilder.releaseEntityHierarchy(_:)`.
  4. Tạo mới `NET_ver1/Features/AboutView.swift` (nút `info.circle` trên `topBar`) hiển thị tên ứng dụng `NÉT`, phiên bản `1.0.0`, bản quyền `© 2026 Võ Vũ Minh Hoàng. All rights reserved.` và màn hình/liên kết Chính sách bảo mật; giới hạn `maxWidth: 640` cho các thanh điều khiển để tương thích màn hình iPad 4:3.
- **Phòng ngừa & Test**: `FigureAssetTests.testAppStoreComplianceAndEntityMemoryRelease`.

---

## Biểu Mẫu Nhập Liệu Chuẩn Khi Gặp Bug Mới (Template)

Mỗi khi phát sinh lỗi mới, copy mẫu sau và thêm vào danh sách:

```markdown
### BUG-[MÃ_SỐ]: [TÊN LỖI NGẮN GỌN]
- **Phân loại**: [Asset 3D / RealityKit / Concurrency / Camera / Vision / UI / Logic]
- **Mức độ**: [Nghiêm trọng / Cao / Trung bình / Thấp]
- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  [Dòng thông báo lỗi nguyên bản bằng tiếng Anh, Crash log, hoặc XCTest assertion message]
  ```
- **Triệu chứng**: [Mô tả hiện tượng xuất hiện, có phải lỗi im lặng không]
- **Nguyên nhân gốc rễ**: [Tại sao lỗi xảy ra, phân tích sâu về mã nguồn / thư viện / phần cứng]
- **Giải pháp**: [Cách thức đã xử lý cụ thể, đoạn code sửa đổi]
- **Phòng ngừa & Test**: [Unit test nào đã được thêm vào để chặn lỗi này tái phát]
```
