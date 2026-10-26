# Đặt người 3D vào app

## Tạo lại asset từ file Mixamo

Mỗi tạo dáng là **một file USDZ riêng** trong `NET_ver1/Assets/Resources/`:

```
NET_ver1/Assets/Resources/
├── pose-seated-straight.usdz
├── pose-seated-chin.usdz
├── pose-seated-lean.usdz
├── pose-standing-straight.usdz
├── pose-standing-hip.usdz
└── pose-standing-aside.usdz
```

Tên file phải đúng `pose-<pose.id>.usdz`. Đổi tên thì app không tìm thấy và âm thầm
dùng hình khối.

## Chạy script

```bash
/Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/bake_poses.py
```

Script đọc 6 file `.fbx` trong `~/Downloads`, nướng từng tạo dáng thành mesh tĩnh và
xuất ra thư mục trên. Không cần mở Blender bằng giao diện.

| `pose.id` | File Mixamo cần tải |
|---|---|
| `seated-straight` | `Sitting Idle.fbx` |
| `seated-chin` | `Thinking.fbx` |
| `seated-lean` | `Sitting.fbx` |
| `standing-straight` | `Idle.fbx` |
| `standing-hip` | `Female Standing Pose.fbx` |
| `standing-aside` | `Look Around.fbx` |

Khi tải từ Mixamo, giữ nguyên hai ô trong hộp thoại Download:

- **Format**: `FBX Binary (.fbx)`
- **Skin**: `With Skin`

## Vì sao không gộp 6 clip vào một file

Đây là điều tốn nhiều công nhất để tìm ra, nên ghi lại:

USD **chỉ giữ một** quan hệ `skel:animationSource` từ `SkelRoot` tới
`SkelAnimation`. RealityKit đọc animation **qua đúng quan hệ đó**.

Ghép 6 clip vào một file `.usdz` sẽ cho ra file:

- hợp lệ về mặt USD, `usdcat` đọc bình thường
- đủ cả 6 tên animation
- nhưng `availableAnimations` trả về **rỗng**, app rơi về xoay khớp

Không có lỗi nào được in ra. Build sạch, test khác vẫn xanh.

Nên script **nướng** từng tạo dáng thành mesh tĩnh: không xương, không animation.
Đúng brief — người 3D đứng yên, không tự chuyển động.

## Ba lỗi khác đã gây mất thời gian, để lại để không phải đoán lại

**1. `transforms_clear` phá hỏng tư thế.**

Lệnh này xoá tư thế mà clip vừa áp, đưa người về T-pose. Nướng ra kết quả là người
đứng thẳng cho cả 6 tạo dáng. Script hiện không gọi lệnh đó.

**2. Blender 4.4+ cần gán `action_slot`.**

Gán `animation_data.action` mà không gán slot thì action chạy trên slot rỗng, xương
không nhận chuyển động. Kết quả: 6 file có **hash giống hệt nhau**, không báo lỗi.

`tools/bake_poses.py` gán slot, và có test chặn lại đúng lỗi này.

**3. Xuất `.usda` làm file nặng 4,5 lần.**

`.usda` là USD dạng chữ. Xuất `.usdc` (nhị phân) giảm từ 61 MB xuống 13,6 MB.
RealityKit đọc cả hai như nhau.

> Xem danh mục đầy đủ các lỗi kỹ thuật và lỗi im lặng đã xử lý tại [Nhật Ký Lỗi (BUG-LOG.md)](BUG-LOG.md).

## Test bảo vệ

`Tests/NET_ver1Tests/FigureAssetTests.swift` kiểm:

- đủ 6 file trong bundle
- mỗi tạo dáng nạp được, chiều cao hợp lệ
- **6 tạo dáng khác nhau thật** — chặn lỗi nướng ra 6 bản giống nhau
- vật liệu của app tới được **mọi** mesh, kể cả mesh khớp nằm sâu trong cây prim
- kích thước file trong khoảng hợp lý

Đổi xong asset phải chạy test này. Nếu `testPosesAreActuallyDifferent` đỏ thì
tư thế chưa được nướng, dù trông mọi thứ vẫn bình thường.

## Về bản quyền

Mixamo **miễn phí thương mại**, kể cả app trả phí — không cần mua Creative Cloud.

Sketchfab phần lớn model **không** cho thương mại. Nếu định bán app thì dùng Mixamo.
