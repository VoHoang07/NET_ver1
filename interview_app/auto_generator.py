#!/usr/bin/env python3
"""NET_ver1 Auto Question Generator.
Phân chia rõ ràng 3 dạng câu hỏi:
  1. Thực tế (Tình huống thực tế, bài toán sản phẩm, nhiếp ảnh & trải nghiệm người dùng)
  2. Kiến trúc và hàm cốt lõi (Clean Architecture, luồng dữ liệu, giải thích sâu các hàm cốt lõi)
  3. Bug (Toàn bộ 20 sự cố kỹ thuật & lỗi thực tế trích xuất từ docs/BUG-LOG.md)
"""

import json
import os
import re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
BUG_LOG_PATH = os.path.join(PROJECT_ROOT, "docs", "BUG-LOG.md")
QUESTIONS_PATH = os.path.join(BASE_DIR, "questions.json")

# 3 Dạng câu hỏi chuẩn xác theo yêu cầu:
CAT_REAL = "Thực tế"
CAT_ARCH = "Kiến trúc và hàm cốt lõi"
CAT_BUGS = "Bug"


def parse_bugs_from_bug_log():
    """Tự động đọc toàn bộ bug trong docs/BUG-LOG.md và chuyển thành dạng câu hỏi 'Bug'."""
    if not os.path.exists(BUG_LOG_PATH):
        return []

    with open(BUG_LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    pattern = r"### (BUG-\d{3}):\s*([^\n]+)\n(.*?)(?=\n### BUG-|\n## Biểu Mẫu|\Z)"
    matches = re.findall(pattern, content, re.DOTALL)

    bug_questions = []

    for bug_id, title, body in matches:
        category_match = re.search(r"- \*\*Phân loại\*\*:\s*([^\n]+)", body)
        severity_match = re.search(r"- \*\*Mức độ\*\*:\s*([^\n]+)", body)
        error_match = re.search(r"- \*\*Thông báo lỗi gốc.*?\*\*:\s*```(?:text)?\n(.*?)```", body, re.DOTALL)
        symptom_match = re.search(r"- \*\*Triệu chứng\*\*:\s*([^\n]+(?:\n(?!\s*- \*\*|\n---).*)*)", body)
        cause_match = re.search(r"- \*\*Nguyên nhân gốc rễ\*\*:\s*([^\n]+(?:\n(?!\s*- \*\*|\n---).*)*)", body)
        solution_match = re.search(r"- \*\*Giải pháp\*\*:\s*([^\n]+(?:\n(?!\s*- \*\*|\n---).*)*)", body)
        test_match = re.search(r"- \*\*Phòng ngừa & Test\*\*:\s*([^\n]+(?:\n(?!\s*- \*\*|\n---).*)*)", body)

        sub_cat = category_match.group(1).strip() if category_match else "Asset 3D"
        severity = severity_match.group(1).strip() if severity_match else "Cao"
        error_msg = error_match.group(1).strip() if error_match else ""
        symptom = symptom_match.group(1).strip().rstrip("-").strip() if symptom_match else ""
        cause = cause_match.group(1).strip().rstrip("-").strip() if cause_match else ""
        solution = solution_match.group(1).strip().rstrip("-").strip() if solution_match else ""
        test_info = test_match.group(1).strip().rstrip("-").strip() if test_match else ""

        if "Nghiêm trọng" in severity:
            difficulty = "Senior"
        elif "Cao" in severity:
            difficulty = "Senior" if "Concurrency" in sub_cat or "RealityView" in sub_cat else "Mid"
        else:
            difficulty = "Mid"

        error_section = ""
        if error_msg:
            error_section = f"**Dòng thông báo lỗi hoặc Assert phát hiện lỗi**:\n```text\n{error_msg}\n```\n\n"

        question_text = f"""[Dạng câu hỏi: BUG TRONG DỰ ÁN — {bug_id} | Phân loại: {sub_cat}]

**Hiện tượng / Triệu chứng**:
{symptom}

{error_section}**Yêu cầu giải quyết**:
1. Hãy phân tích bản chất và nguyên nhân gốc rễ (Root Cause) gây ra lỗi này.
2. Nêu giải pháp khắc phục cụ thể trong mã nguồn của dự án NET_ver1.
3. Làm sao để viết Unit Test tự động chặn đứng lỗi này không bị tái diễn trong tương lai?"""

        ideal_answer = f"""1. **Nguyên nhân gốc rễ**:
{cause}

2. **Giải pháp khắc phục**:
{solution}

3. **Biện pháp phòng ngừa & Unit Test**:
{test_info}"""

        # Loại bỏ các khối code ```...``` trước khi trích xuất inline code `...` để tránh bắt nhầm cả đoạn dài
        body_without_fenced = re.sub(r"```.*?```", "", body, flags=re.DOTALL)
        inline_codes = [w.strip("`*.,() ") for w in re.findall(r"`([^`\n]+)`", body_without_fenced)]
        keywords = [k for k in inline_codes if 2 < len(k) <= 45]
        keywords.append(bug_id)
        keywords.append(sub_cat.split("/")[0].strip())
        if "RealityKit" in body:
            keywords.append("RealityKit")
        if "USDZ" in body:
            keywords.append("USDZ")
        if "Blender" in body:
            keywords.append("Blender")
        if "MainActor" in body:
            keywords.append("MainActor")
        keywords = list(dict.fromkeys([k for k in keywords if len(k) > 2]))[:8]

        bug_questions.append({
            "id": f"Q-{bug_id}",
            "title": f"[{bug_id}] {title.strip()}",
            "category": CAT_BUGS,
            "subCategory": sub_cat,
            "difficulty": difficulty,
            "relatedFiles": ["docs/BUG-LOG.md"],
            "codeSnippet": error_msg if error_msg else f"// Sự cố: {title}\n// Phân loại: {sub_cat}",
            "question": question_text,
            "hints": [
                f"Sự cố thuộc mảng kỹ thuật: {sub_cat}.",
                "Kiểm tra xem đây là lỗi biên dịch, lỗi crash runtime hay lỗi im lặng (Silent Failure).",
                f"Bài kiểm tra chặn lỗi tái phát: {test_info.split(';')[0] if test_info else 'Unit Test trong NET_ver1Tests'}"
            ],
            "rubric": {
                "keywords": keywords,
                "criteria": [
                    "Chỉ ra được nguyên nhân gốc rễ kỹ thuật của sự cố.",
                    "Trình bày giải pháp sửa đổi mã nguồn chính xác.",
                    "Đề cập đến unit test hoặc cơ chế phòng vệ chống lỗi tái phát."
                ]
            },
            "idealAnswer": ideal_answer
        })

    return bug_questions


def get_real_world_scenario_questions():
    """Dạng 1: Thực tế (Các bài toán thực tế khi chụp ảnh ngoài đời, UX sản phẩm & tình huống vận hành thực tế)."""
    return [
        {
            "id": "Q-REAL-001",
            "title": "Chụp chân dung trong quán cà phê chật: Tại sao dùng Zoom thay vì bắt người mẫu lùi và giới hạn trần 2.0x?",
            "category": CAT_REAL,
            "subCategory": "Không gian chụp & Tiêu cự thực tế",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/SceneComposer.swift", "NET_ver1/Features/CameraView.swift"],
            "codeSnippet": "// Trong SceneComposer.swift:\nnonisolated static let minimumZoom: CGFloat = 1.0\nnonisolated static let maximumZoom: CGFloat = 2.0\n\nstatic func suggestedZoom(pose: ShootingPose, viewport: CGSize, availableDepth: CGFloat?, currentZoom: CGFloat) -> CGFloat {\n    guard viewport.width > 0, availableDepth != nil else {\n        return min(max(currentZoom, minimumZoom), maximumZoom)\n    }\n    let depth = max(availableDepth ?? 0, 0.5)\n    let wantedDistance = pose.standoffInHeads * BodyPoseReference.typicalHeadHeight\n    guard depth < wantedDistance else { return minimumZoom }\n    return min(max(wantedDistance / depth, minimumZoom), maximumZoom)\n}",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Không gian chụp hẹp]\n\nNgoài đời thực, người dùng rất hay chụp ảnh chân dung trong quán cà phê nhỏ hoặc phòng khách hẹp, nơi người mẫu hoặc người chụp bị vướng tường/bàn ghế và **không thể bước lùi thêm 1.5 - 2 mét** để đạt khoảng cách tiêu chuẩn.\n\n1. Tại sao `SceneComposer` giải quyết bài toán phòng chật bằng cách đề xuất `suggestedZoom` thay vì hiện thông báo bắt người dùng lùi lại? Sự khác biệt quang học giữa 'Zoom vào' và 'Bước lùi/tiến' trong khung hình là gì?\n2. Tại sao ứng dụng khoá trần `maximumZoom = 2.0` và cố ý không làm thanh trượt (slider) zoom thủ công mà chỉ có nút 'Lấy góc này'?",
            "hints": [
                "Ở phòng chật, vị trí đứng lùi thêm 2m không tồn tại trong không gian vật lý.",
                "Zoom giữ nguyên vị trí đứng của người mẫu và thu hẹp trường nhìn (FOV), nhưng cắt bớt nền.",
                "Zoom vượt quá 2x trên cảm biến điện thoại gây vỡ hạt, mất chi tiết và biến dạng phối cảnh chân dung."
            ],
            "rubric": {
                "keywords": ["suggestedZoom", "maximumZoom", "phòng chật", "wantedDistance", "availableDepth", "Lấy góc này", "2.0", "trường nhìn"],
                "criteria": [
                    "Giải thích thực tế: trong quán cà phê/phòng nhỏ không có chỗ để lùi, nên điều chỉnh zoom giúp người mẫu đứng yên một chỗ.",
                    "Phân tích lý do giới hạn maximumZoom = 2.0: tránh mất chi tiết do crop cảm biến quá mức và giữ tự nhiên cho ảnh chân dung.",
                    "Giải thích triết lý UX nút 'Lấy góc này' thay cho slider zoom: người dùng phổ thông không hiểu hệ số zoom, app tự quyết định giúp họ không đau đầu."
                ]
            },
            "idealAnswer": "1. **Giải quyết bài toán phòng chật bằng `suggestedZoom`**:\n- Trong thực tế (quán cà phê, phòng ăn nhỏ), khoảng cách lý tưởng `wantedDistance = pose.standoffInHeads * typicalHeadHeight` đôi khi không khả thi về mặt vật lý. Nếu app cứ báo lỗi 'Hãy lùi ra xa', người dùng sẽ bế tắc vì lưng đã chạm tường.\n- Thay vào đó, `SceneComposer` tính tỉ số `wantedDistance / depth` để đề xuất mức zoom phù hợp. Điểm khác biệt quan trọng là: **zoom giữ nguyên vị trí người mẫu trong phòng** và chỉ thu hẹp trường nhìn (FOV) của ống kính để chủ thể đạt kích thước chuẩn trong khung mà không cần di chuyển chân.\n\n2. **Lý do khoá trần `maximumZoom = 2.0` và bỏ thanh trượt Zoom**:\n- **Trần 2.0x**: Trên điện thoại, zoom quá lớn (như 3x–5x crop kỹ thuật số) làm giảm độ phân giải, gây nhiễu hạt (noise) và cắt cụt hoàn toàn các đường dẫn thị giác của hậu cảnh. Nhiếp ảnh gia thực thụ không đứng sát rồi zoom 5x mà kết hợp bước chân với tiêu cự vừa phải (1x–2x).\n- **Nút 'Lấy góc này' thay vì Slider Zoom**: Người dùng phổ thông không biết con số 1.4x hay 1.8x có ý nghĩa gì. Việc trao thanh trượt là đẩy gánh nặng quyết định lại cho người dùng — đi ngược tinh thần 'hướng dẫn không đau đầu' của NÉT."
        },
        {
            "id": "Q-REAL-002",
            "title": "Người mẫu tạo dáng quay nghiêng mặt (Profile): Xử lý khi Vision không thấy khuôn mặt",
            "category": CAT_REAL,
            "subCategory": "Thị giác máy tính & Trải nghiệm tạo dáng",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Domain/CaptureCheck.swift", "NET_ver1/Cores/FrameAnalyzer.swift"],
            "codeSnippet": "// Trong CaptureCheck.swift:\nvar isEmpty: Bool {\n    subjectRect == nil && !hasPerson && !hasSubject && bodyPose == nil\n}",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Tư thế nhìn nghiêng]\n\nKhi chụp chân dung nghệ thuật (ví dụ tư thế `standing-aside` hoặc khi người mẫu quay mặt nhìn nghiêng sang cửa sổ), bộ phát hiện khuôn mặt `VNDetectFaceRectanglesRequest` của Apple Vision thường trả về mảng rỗng (`faces.isEmpty == true`) vì không nhìn thấy đủ hai mắt và sống mũi.\n\n1. Chuyện gì sẽ xảy ra với trải nghiệm người dùng nếu thuộc tính `CaptureMeasurements.isEmpty` chỉ kiểm tra `subjectRect == nil && !hasPerson`?\n2. Việc bổ sung `bodyPose == nil` vào điều kiện `isEmpty` kết hợp với `VNDetectHumanBodyPoseRequest` giải quyết tình huống thực tế này như thế nào?",
            "hints": [
                "Khi quay nghiêng mặt, Vision mất dấu khuôn mặt (hasPerson = false, subjectRect = nil).",
                "Tuy nhiên VNDetectHumanBodyPoseRequest vẫn nhận diện tốt khớp vai, cổ, hông.",
                "Tránh báo lỗi vô lý 'Chưa nhận ra người' khi người mẫu đang đứng ngay trước ống kính."
            ],
            "rubric": {
                "keywords": ["isEmpty", "bodyPose", "hasPerson", "subjectRect", "quay nghiêng", "VNDetectHumanBodyPoseRequest", "vai", "hông"],
                "criteria": [
                    "Phân tích tình huống thực tế: khi người mẫu quay nghiêng hoặc cúi nhẹ, face detector thất bại dù người vẫn đứng giữa khung hình.",
                    "Chỉ ra nếu bỏ qua bodyPose, app sẽ coi khung hình là trống hoặc báo 'Chưa nhận ra người' gây ức chế lớn.",
                    "Giải thích cách bodyPose giữ cho luồng chấm điểm hoạt động liên tục dựa trên khung xương vai/hông."
                ]
            },
            "idealAnswer": "1. **Hệ quả nếu chỉ dựa vào nhận diện khuôn mặt (`hasPerson` / `subjectRect`)**:\nTrong nhiếp ảnh chân dung, người mẫu thường xuyên tạo dáng nhìn nghiêng (profile), nhìn xa xăm hoặc hơi cúi đầu. Lúc này `VNDetectFaceRectanglesRequest` không tìm được mặt nên `hasPerson = false` và `subjectRect = nil`. Nếu `CaptureMeasurements.isEmpty` chỉ dựa vào mặt, ứng dụng sẽ lập tức ngắt luồng chấm hoặc hiển thị cảnh báo vô lý: *'Chưa nhận ra người trong khung'* ngay cả khi người mẫu đang đứng sừng sững ngay chính giữa màn hình.\n\n2. **Giải pháp kết hợp `bodyPose` trong `CaptureMeasurements.isEmpty`**:\nDù khuôn mặt bị khuất góc, `VNDetectHumanBodyPoseRequest` vẫn nhận diện rất tốt các khớp lớn của cơ thể (hai vai `leftShoulder`/`rightShoulder`, cổ `neck`, hông `hip`). Nhờ kiểm tra thêm `&& bodyPose == nil`, miễn là hệ thống thấy khung xương cơ thể hợp lệ (`bodyPose.isUsable`), ứng dụng vẫn duy trì trạng thái nhận diện chủ thể và tiếp tục hướng dẫn căn chỉnh tư thế mượt mà."
        },
        {
            "id": "Q-REAL-003",
            "title": "Đèn trần chiếu đỉnh đầu gây bóng tối dưới hốc mắt: Phát hiện bóng đổ trên mặt ngoài thực tế",
            "category": CAT_REAL,
            "subCategory": "Ánh sáng nhiếp ảnh thực tế",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Cores/FrameAnalyzer.swift", "NET_ver1/Domain/CaptureCheck.swift"],
            "codeSnippet": "// Trong FrameAnalyzer.swift:\nlet innerVisionBox = CGRect(\n    x: visionBox.minX + visionBox.width * 0.2,\n    y: visionBox.minY + visionBox.height * 0.2,\n    width: visionBox.width * 0.6,\n    height: visionBox.height * 0.6\n)\nlet ringVisionBox = CGRect(\n    x: innerVisionBox.minX - visionBox.width * 0.4,\n    y: innerVisionBox.minY - visionBox.height * 0.4,\n    width: innerVisionBox.width + visionBox.width * 0.8,\n    height: innerVisionBox.height + visionBox.height * 0.8\n)\nreturn center / ring // faceShadowRatio",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Lỗi ánh sáng bóng đổ trên mặt]\n\nMột lỗi cực kỳ phổ biến của người không chuyên khi chụp ảnh chân dung trong nhà hoặc dưới nắng trưa là để người mẫu đứng ngay dưới đèn trần / mặt trời chiếu thẳng, làm hốc mắt và dưới mũi bị tối sầm (raccoon eyes), trong khi nền xung quanh vẫn rất sáng nên cảm biến đo sáng tổng thể không phát hiện ra.\n\n1. Tại sao chỉ đo độ sáng trung bình toàn ảnh (`underexposedRatio` / `overexposedRatio`) không thể bắt được lỗi bóng đổ trên khuôn mặt này?\n2. Phân tích cách hàm `faceShadowRatio` trong `FrameAnalyzer` dùng 2 vùng hình chữ nhật `innerVisionBox` (60% tâm mặt) và `ringVisionBox` (vành quanh mặt) để bắt chính xác lỗi này ngoài thực tế.",
            "hints": [
                "Nền sáng + áo sáng làm trung bình toàn ảnh vẫn đủ sáng, chỉ riêng vùng mắt/mũi bị tối.",
                "Lấy 60% trung tâm bbox mặt để loại bỏ phần tóc đen ở viền ngoài.",
                "So sánh tỉ số luma trung tâm mặt chia cho vành xung quanh (minimumFaceLuminance = 0.82)."
            ],
            "rubric": {
                "keywords": ["faceShadowRatio", "innerVisionBox", "ringVisionBox", "0.6", "minimumFaceLuminance", "0.82", "bóng đổ", "tóc"],
                "criteria": [
                    "Giải thích tại sao đo sáng toàn khung thất bại: vùng mặt chỉ chiếm diện tích nhỏ, nền sáng át đi vùng tối trên mặt.",
                    "Giải thích tại sao co vùng đo vào 60% tâm mặt (innerVisionBox): để loại trừ viền tóc tối màu làm lệch kết quả.",
                    "Phân tích tỉ số center / ring < 0.82 chứng tỏ vùng mặt đang tối hơn môi trường ngay sát quanh đầu -> cảnh báo người mẫu bước ra hướng sáng."
                ]
            },
            "idealAnswer": "1. **Tại sao đo sáng toàn khung không phát hiện được bóng mặt**:\nKhi chụp dưới đèn chiếu đỉnh đầu hoặc đứng dưới tán cây, hậu cảnh xung quanh vẫn sáng rực nên tỉ lệ tối toàn khung (`underexposedRatio`) rất thấp. Tuy nhiên vùng trung tâm khuôn mặt (hốc mắt, gò má, dưới mũi) lại bị bóng đổ làm tối sầm. Người không có kinh nghiệm nhiếp ảnh thường chỉ nhìn nụ cười mà không nhận ra mặt bị tối cho đến khi xem lại ảnh.\n\n2. **Cơ chế `innerVisionBox` vs `ringVisionBox` trong `FrameAnalyzer.faceShadowRatio`**:\n- **Co vào 60% lõi khuôn mặt (`innerVisionBox`)**: Bbox khuôn mặt của Vision bao gồm cả phần tóc hai bên thái dương và đỉnh đầu. Nếu tính cả toàn bộ bbox, mái tóc màu đen sẽ làm độ sáng trung bình mặt bị tụt giả tạo. Việc lấy 60% vùng lõi ở giữa (`0.2` đến `0.8`) đảm bảo chỉ đo đúng vùng da trán, mắt, mũi và má.\n- **So sánh với vành khuyên (`ringVisionBox`)**: Mở rộng vùng bao quanh mặt để lấy độ sáng môi trường kế cận. Khi tỉ số `center / ring < QualityThresholds.minimumFaceLuminance (0.82)`, hệ thống kết luận khuôn mặt đang tối hơn vùng xung quanh quá 18% và nhắc người dùng chỉnh lại hướng đứng nhận sáng."
        },
        {
            "id": "Q-REAL-004",
            "title": "Chụp ảnh ở nơi đông người & nền rối: Chọn đúng người mẫu chính và tính độ bận nền (`backgroundClutter`)",
            "category": CAT_REAL,
            "subCategory": "Bối cảnh thực tế ngoài trời & Quán đông",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Cores/FrameAnalyzer.swift", "NET_ver1/Domain/CaptureCheck.swift"],
            "codeSnippet": "// Trong FrameAnalyzer.swift:\nlet poseObservations = (poseRequest.results ?? [])\n    .filter { $0.confidence > 0.3 }\n    .sorted { $0.confidence > $1.confidence }\n\n// Trong backgroundClutter(_ mask: CVPixelBuffer):\nif value > 40 { x += 2; continue } // Thuộc vùng người -> bỏ qua\nif abs(value - right) > 40 || abs(value - down) > 40 { edges += 1 }",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Bối cảnh đông người & Hậu cảnh rối]\n\nKhi người dùng chụp ảnh ở phố đi bộ hoặc quán cà phê đông khách, trong khung hình thường xuyên có người qua đường lọt vào góc ảnh, hoặc hậu cảnh phía sau có quá nhiều biển hiệu, dây điện làm người mẫu bị chìm vào nền.\n\n1. Khi có nhiều người trong khung hình, `FrameAnalyzer` và `CaptureCheckEvaluator` xử lý thế nào để: (a) lấy đúng tư thế của người mẫu chính và (b) cảnh báo nếu số lượng người không khớp với chế độ chụp (`expectedSubjectCount`)?\n2. Thuật toán `backgroundClutter(_ mask:)` sử dụng mặt nạ phân tách người (`VNGeneratePersonSegmentationRequest`) như thế nào để đo độ rối của riêng phần nền mà không tính nhầm họa tiết quần áo của người mẫu?",
            "hints": [
                "Lọc poseObservations có confidence > 0.3 và sắp xếp giảm dần theo confidence.",
                "Kiểm tra detectedPersonCount so với mode.expectedSubjectCount.",
                "Trong mask segmentation, pixel > 40 thuộc về cơ thể người nên được continue bỏ qua khi đếm biên cạnh (edges)."
            ],
            "rubric": {
                "keywords": ["confidence", "expectedSubjectCount", "detectedPersonCount", "VNGeneratePersonSegmentationRequest", "backgroundClutter", "value > 40", "edges", "quần áo"],
                "criteria": [
                    "Chỉ ra cách chọn người mẫu chính bằng cách lọc confidence > 0.3 và lấy observation có độ tin cậy cao nhất, kết hợp kiểm tra detectedPersonCount.",
                    "Giải thích cơ chế backgroundClutter: dùng person segmentation mask, bỏ qua mọi pixel có giá trị > 40 (vùng người mẫu) để hoạ tiết áo kẻ sọc không bị tính là nền rối.",
                    "Phân tích cách đếm mật độ cạnh (biến thiên cục bộ > 40 với pixel bên phải/bên dưới) trên vùng nền để đánh giá mức độ rối."
                ]
            },
            "idealAnswer": "1. **Xử lý nhiều người trong khung hình**:\n- **Chọn người mẫu chính để chấm tư thế**: `FrameAnalyzer` lọc các `VNHumanBodyPoseObservation` có `confidence > 0.3` và sắp xếp giảm dần theo `confidence`. Người mẫu đứng gần và rõ nhất ở trung tâm sẽ có confidence cao nhất (`poseObservations.first`).\n- **Kiểm soát số người theo Mode**: `CaptureCheckEvaluator.checkComposition` đối chiếu `detectedPersonCount` với `mode.expectedSubjectCount`. Nếu đang ở chế độ chụp chân dung 1 người mà có người lạ đi ngang vào khung, tiêu chí `composition` sẽ báo rõ: *'Cần 1 người nhưng đang có 2'*.\n\n2. **Đo độ bận của nền (`backgroundClutter`) không lẫn với quần áo người mẫu**:\n- Nếu đo mật độ cạnh (edge density) trên toàn bức ảnh, một người mẫu mặc áo kẻ caro hoặc váy hoa sẽ bị thuật toán báo nhầm là 'Nền rối'.\n- Do đó, `FrameAnalyzer` chạy `VNGeneratePersonSegmentationRequest` (mức `.fast`) để tạo mặt nạ 8-bit tách người khỏi nền. Trong hàm `backgroundClutter`, mọi pixel có `value > 40` (thuộc cơ thể người mẫu) đều được `continue` bỏ qua. Thuật toán chỉ tính độ chênh lệch biên (`abs(value - right) > 40 || abs(value - down) > 40`) trên các pixel thực sự thuộc về hậu cảnh phía sau."
        },
        {
            "id": "Q-REAL-005",
            "title": "Xử lý bất định ngoài thực tế: Tại sao khi không đo được mắt (`eyesOpen == nil`), Auto-Capture vẫn cho phép chụp?",
            "category": CAT_REAL,
            "subCategory": "Đánh đổi UX & Quyết định chụp tự động",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Cores/FrameAnalyzer.swift", "NET_ver1/Features/CameraView.swift"],
            "codeSnippet": "// Trong FrameAnalyzer.swift:\nprivate static func eyesOpen(from faces: [DetectedFace]) -> Bool? {\n    guard let ratio = faces.first?.eyeOpenRatio else { return nil }\n    return ratio > 0.035\n}\n\n// Trong CameraView.swift:\nlet eyesOpen = analysis.eyesOpen ?? true",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Đánh đổi UX khi thiếu dữ liệu cảm biến]\n\nKhi chụp chân dung toàn thân (Full-body) ở khoảng cách 2.5–3 mét hoặc khi người mẫu đeo kính râm / đội mũ rộng vành, `VNDetectFaceLandmarksRequest` không đủ độ phân giải để đo khoảng cách giữa mí mắt trên và mí mắt dưới, nên trả về `eyesOpen = nil`.\n\n1. Tại sao đội ngũ phát triển quyết định dùng kiểu trả về 3 trạng thái `Bool?` (`true`, `false`, `nil`) và gán `let eyesOpen = analysis.eyesOpen ?? true` thay vì trả về `false` mặc định?\n2. Hàm `eyeOpenRatio` tính tỉ lệ mở mắt dựa trên một mắt (`leftEye ?? rightEye`) và chuẩn hoá theo `faceBox.height` giải quyết vấn đề thực tế nào khi người mẫu đứng xa/gần khác nhau?",
            "hints": [
                "Phân biệt rõ 'biết chắc người mẫu đang nhắm mắt (false)' với 'không đủ dữ liệu để đo (nil)'.",
                "Nếu nil coi là false, chụp toàn thân ở xa sẽ không bao giờ tự động chụp được.",
                "Chia khoảng cách mí mắt (upper - lower) cho faceBox.height giúp bất biến với khoảng cách đứng."
            ],
            "rubric": {
                "keywords": ["eyesOpen", "Bool?", "nil", "eyeOpenRatio", "0.035", "faceBox.height", "bỏ lỡ khoảnh khắc", "chụp toàn thân"],
                "criteria": [
                    "Phân biệt rõ 2 trạng thái: false (xác nhận đang nhắm mắt -> chặn chụp) và nil (mặt nhỏ/nghiêng không đo được -> cho phép chụp).",
                    "Giải thích đánh đổi sản phẩm: nếu chặn chụp khi nil, tính năng Auto-Capture sẽ tê liệt hoàn toàn ở các góc chụp toàn thân hoặc góc nghiêng.",
                    "Giải thích chuẩn hoá (upper - lower) / faceBox.height và dùng leftEye ?? rightEye giúp hàm hoạt động ổn định dù người đứng xa hay hơi xoay mặt."
                ]
            },
            "idealAnswer": "1. **Triết lý đánh đổi sản phẩm (`eyesOpen ?? true`)**:\n- Có sự khác biệt bản chất giữa **'Biết chắc đang nhắm mắt' (`false`)** và **'Không đo được mắt' (`nil`)**. Khi người mẫu đứng xa chụp toàn thân, đeo kính, hoặc quay nghiêng góc mặt, khuôn mặt quá nhỏ để Vision trích xuất đủ 8 điểm landmark mí mắt.\n- Nếu gộp `nil` thành `false`, tính năng chụp tự động (Auto-Capture) sẽ bị khoá chết hoàn toàn trong các buổi chụp toàn thân hoặc góc mặt nghiêng — người mẫu đứng mỏi chân mà máy không bao giờ bấm chụp. Do đó, chỉ chặn chụp khi phát hiện chắc chắn mắt đang khép (`ratio <= 0.035`), còn khi `nil` thì mặc định cho phép chụp (`?? true`).\n\n2. **Kỹ thuật đo `eyeOpenRatio` bền bỉ ngoài thực tế**:\n- **Dùng `landmarks.leftEye ?? landmarks.rightEye`**: Khi người mẫu hơi xoay mặt, Vision thường bị mất landmark của mắt bên khuất. Lấy một mắt khả dụng giúp hàm không bị đứt quãng.\n- **Chia cho `faceBox.height`**: Khoảng cách pixel tuyệt đối giữa hai mí mắt thay đổi theo khoảng cách đứng. Chia `(upper - lower)` cho chiều cao khuôn mặt `faceBox.height` tạo ra tỉ lệ bất biến theo khoảng cách, cho phép dùng một ngưỡng hằng số duy nhất `0.035`."
        },
        {
            "id": "Q-REAL-006",
            "title": "Tâm lý người dùng khi tạo dáng: Tại sao `PostureMatch` cố ý dùng dung sai rộng (20°–25°) và giấu số độ lệch?",
            "category": CAT_REAL,
            "subCategory": "Thiết kế hành vi & Tâm lý người dùng",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Domain/PostureMatch.swift"],
            "codeSnippet": "// Trong PostureMatch.swift:\nif let tilt = measured.shoulderTiltDegrees {\n    let error = abs(tilt - pose.shoulderTilt)\n    if error > 25 { // Sai 25° trở lại mới đáng nhắc\n        let hint = tilt > pose.shoulderTilt ? \"Hạ vai phải xuống một chút\" : \"Nhấc vai phải lên một chút\"\n        issues.append((score: max(0, 1 - error / 50), adjustment: .pose(criterion: .posture, hint: hint)))\n    }\n}",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Tâm lý người chụp & Ngưỡng dung sai]\n\nKhi thử nghiệm thực tế với các cặp đôi đi chụp ảnh, nếu ứng dụng kiểm tra độ nghiêng vai/thân quá khắt khe (ví dụ lệch > 5° là báo lỗi) hoặc hiện thông báo kỹ thuật kiểu *'Vai nghiêng 12.3°, thân lệch 8.5°'*, cả người chụp lẫn người mẫu đều nhanh chóng bực bội và tắt khung hướng dẫn.\n\n1. Tại sao `PostureMatch.poseDeviation` cố ý đặt ngưỡng dung sai rất rộng (`error > 25°` cho vai và `> 20°` cho cột sống) và tách biệt chuỗi số kỹ thuật vào biến `detail` ẩn?\n2. Tại sao khi người mẫu lệch sang bên trái khung hình (`dx < 0`), `PostureMatch.evaluate` lại trả về `.moveRight` thay vì `.moveLeft`, và tại sao chỉ trả về duy nhất `issues.min(by: { $0.score < $1.score })`?",
            "hints": [
                "Con người không phải ma-nơ-canh, tạo dáng tự nhiên luôn có sai số 10-15 độ.",
                "Hướng điều chỉnh là hướng người mẫu cần di chuyển để tiến về tâm khung hình.",
                "Chỉ đưa ra 1 chỉ dẫn tệ nhất (min score) tại một thời điểm để người chụp có thể nói ngắn gọn cho người mẫu."
            ],
            "rubric": {
                "keywords": ["poseDeviation", "25", "20", "detail", "moveRight", "moveLeft", "issues.min", "dung sai"],
                "criteria": [
                    "Giải thích dung sai rộng 20-25°: tạo dáng người thật cần sự thoải mái tự nhiên, bắt chỉnh từng độ làm người mẫu cứng đờ và gây phiền toái.",
                    "Phân tích logic hướng di chuyển: dx = head.x - layout.subjectCenter.x < 0 nghĩa là đang lệch về bên trái, nên hành động khắc phục là dịch sang phải (.moveRight).",
                    "Giải thích việc chọn issues.min (lỗi có điểm thấp nhất): giúp người cầm máy chỉ cần đọc 1 câu ngắn gọn duy nhất cho người mẫu làm theo."
                ]
            },
            "idealAnswer": "1. **Ngưỡng dung sai rộng (20°–25°) và ẩn `detail` kỹ thuật**:\n- Người mẫu ngoài đời không phải ma-nơ-canh và cảm biến Vision trên video 2D luôn có nhiễu đo đạc vài độ theo nhịp thở. Nếu bắt lỗi ở mức 5°–10°, ứng dụng sẽ nhảy cảnh báo liên tục khiến người mẫu căng thẳng, mất tự nhiên. Ngưỡng 20°–25° đảm bảo chỉ khi người mẫu tạo dáng **sai hẳn kiểu** (ví dụ tư thế nghiêng người mà lại đứng thẳng đơ) thì app mới nhắc.\n- Chuỗi số *'Vai nghiêng 12°, thân nghiêng 8°'* được cất vào `detail` (dùng cho debug/log) còn UI chỉ hiển thị chỉ dẫn hành động tự nhiên như *'Hạ vai phải xuống một chút'*.\n\n2. **Logic hướng di chuyển (`.moveRight`) và chọn lỗi nặng nhất (`issues.min`)**:\n- Khi `dx = head.x - layout.subjectCenter.x < 0`, đầu người mẫu đang nằm lệch về bên trái so với tâm bố cục. Để sửa lỗi, người mẫu phải bước **sang phải** (`.moveRight`). Đặt tên enum theo *hành động cần làm* thay vì *vị trí lỗi* giúp UI hiển thị mũi tên chỉ hướng trực tiếp mà không sợ ngược.\n- Khi người mẫu vừa đứng lệch tâm, vừa đứng quá xa, lại vừa lệch vai, họ không thể sửa 3 thứ cùng lúc. Lấy `issues.min(by: { $0.score < $1.score })` chọn ra vấn đề nghiêm trọng nhất để giải quyết tuần tự từng bước."
        },
        {
            "id": "Q-REAL-007",
            "title": "Bài toán phân tầng chất lượng ảnh thực tế: Tại sao phải chia `gate` (Lấy nét, Ánh sáng) và `polish` thay vì cộng điểm trung bình?",
            "category": CAT_REAL,
            "subCategory": "Thuật toán chấm điểm chất lượng ảnh",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/CaptureCheck.swift"],
            "codeSnippet": "// Trong CaptureCheck.swift:\nvar isGate: Bool {\n    switch self {\n    case .sharpness, .lighting: true\n    case .shadow, .horizon, .posture, .composition, .background: false\n    }\n}\n\ninit(failures: [QualityCriterion], polish: [QualityCriterion]) {\n    if failures.isEmpty {\n        self = polish.isEmpty ? .ideal : .good\n    } else {\n        self = .notReady\n    }\n}",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Đánh giá chất lượng bức ảnh]\n\nGiả sử một bức ảnh có bố cục tuyệt đẹp, người mẫu tạo dáng chuẩn 100%, đường chân trời thẳng tắp, nền sạch sẽ — nhưng **ảnh bị nhoè mờ (out of focus) hoặc cháy sáng trắng xoá**. Nếu dùng thuật toán cộng điểm trung bình tuyến tính thông thường, bức ảnh này vẫn đạt 75/100 điểm ('Khá tốt') dù ngoài đời thực bức ảnh đó hoàn toàn vô giá trị và phải xoá bỏ.\n\n1. Phân tích cách `QualityCriterion` và `CaptureStatus` trong `CaptureCheck.swift` giải quyết nghịch lý này thông qua hai nhóm `gate` và `polish`.\n2. Tại sao hàm `weight(for mode: CaptureMode)` phải đảm bảo tổng trọng số của mọi tiêu chí trong mỗi chế độ chụp (như `.portrait` hay `.object`) luôn cộng lại bằng đúng **100**?",
            "hints": [
                "Gate (sharpness, lighting): điều kiện sống còn, hỏng 1 cái là bức ảnh không thể cứu vãn bằng hậu kỳ -> status = .notReady.",
                "Polish (shadow, horizon, posture, composition, background): điều kiện làm đẹp thêm -> đạt gate nhưng thiếu polish vẫn đạt .good.",
                "Ở mode .object không có posture và shadow (trọng số = 0), nên phải phân bổ lại trọng số sang composition và background để tổng vẫn bằng 100."
            ],
            "rubric": {
                "keywords": ["isGate", "gate", "polish", "sharpness", "lighting", "notReady", "good", "ideal", "weight", "100"],
                "criteria": [
                    "Giải thích sự thất bại của mô hình cộng điểm tuyến tính: không phân biệt được lỗi chí mạng (mờ/cháy sáng) với lỗi thẩm mỹ nhỏ.",
                    "Phân tích cơ chế Gate vs Polish: bất kỳ gate nào fail đều đẩy CaptureStatus về .notReady ngay lập tức.",
                    "Giải thích quy tắc bảo toàn tổng trọng số bằng 100 ở mọi CaptureMode để không làm chế độ ít tiêu chí hơn (như .object) bị thiệt điểm tối đa."
                ]
            },
            "idealAnswer": "1. **Phân tách điều kiện cần (`gate`) và điều kiện đủ (`polish`)**:\n- Trong nhiếp ảnh thực tế, các tiêu chí không có vai trò ngang nhau. **Độ nét (`sharpness`)** và **Ánh sáng (`lighting`)** là hai điều kiện tiên quyết (`isGate == true`): một bức ảnh bị rung nhoè hoặc cháy sáng mất chi tiết thì không phần mềm chỉnh ảnh nào cứu được.\n- Ngược lại, các yếu tố `shadow`, `horizon`, `posture`, `composition`, `background` thuộc nhóm tinh chỉnh (`polish`): nếu hơi lệch một chút, bức ảnh vẫn sử dụng được (`CaptureStatus.good`).\n- Do đó, `CaptureStatus.init(failures:polish:)` kiểm tra `failures` (các gate bị trượt) trước tiên: chỉ cần 1 gate trượt là trạng thái lập tức về `.notReady`, ngăn người dùng chụp ra ảnh hỏng.\n\n2. **Bảo toàn tổng trọng số bằng 100 theo từng `CaptureMode`**:\n- Khi chuyển từ chế độ chụp người sang chụp vật thể (`.object`), hai tiêu chí `posture` (15 điểm) và `shadow` trên mặt (5 điểm) không còn ý nghĩa nên có trọng số bằng `0`.\n- Nếu không bù 20 điểm này sang các tiêu chí khác, tổng điểm tối đa của mode `.object` chỉ còn 80/100 — khiến mode chụp vật thể luôn bị trừ điểm oan. Vì vậy, `weight(for: .object)` tăng `composition` từ 15 lên 20 và `background` từ 5 lên 20 (vì chụp tĩnh vật rất cần tách nền sạch), giữ tổng trọng số luôn đúng bằng 100 và được bảo vệ bằng Unit Test."
        },
        {
            "id": "Q-REAL-008",
            "title": "Sự cố mất file 3D hoặc đặt bàn ghế ảo ngược chiều ngoài thực tế: Cơ chế Fallback & Toạ độ bàn trong `GuideSceneBuilder`",
            "category": CAT_REAL,
            "subCategory": "Độ tin cậy hiển thị 3D & Bố cục không gian",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Features/TranslucentSceneView.swift", "NET_ver1/Features/FurnitureBuilder.swift"],
            "codeSnippet": "// Trong GuideSceneBuilder.build(pose:metrics:):\nif pose.usesTable {\n    let furniture = FurnitureBuilder.makeTable(metrics: metrics)\n    furniture.position = SIMD3<Float>(0, 0, 0.35)\n    root.addChild(furniture)\n}\nif let rigged = FigureAssetLoader.load(pose: pose, metrics: metrics) {\n    root.addChild(rigged)\n} else {\n    root.addChild(FigureBuilder.makeFigure(pose: pose, metrics: metrics))\n}",
            "question": "[Dạng câu hỏi: TÌNH HUỐNG THỰC TẾ — Bố cục đạo cụ 3D & Khả năng chống lỗi]\n\nTrong các tư thế ngồi quán cà phê (`seated-straight`, `seated-lean`, `seated-chin`), ứng dụng hiển thị thêm chiếc bàn ảo 3D để người chụp căn vị trí người mẫu ngồi vào bàn thật.\n\n1. Tại sao trong `GuideSceneBuilder.build`, chiếc bàn phải được đặt ở toạ độ `z = +0.35` (dương) thay vì `z = -0.35` (âm)? Hiện tượng thị giác gì sẽ xảy ra trên màn hình nếu đặt nhầm dấu của trục Z?\n2. Tại sao hệ thống duy trì song song cả `FigureAssetLoader.load` (nạp file USDZ) lẫn `FigureBuilder.makeFigure` (dựng bằng hình khối cơ bản)? Điểm rẽ duy nhất tại `GuideSceneBuilder.build` mang lại lợi ích gì khi thêm tư thế mới?",
            "hints": [
                "Người mẫu đứng/ngồi tại gốc Z = 0, còn camera đứng tại Z = +distance nhìn về 0.",
                "Bàn trong ảnh chân dung quán cà phê nằm giữa người mẫu và ống kính máy ảnh.",
                "Nếu thiếu file USDZ cho một tư thế mới, app tự động hiển thị ma-nơ-canh hình khối thay vì màn hình trống."
            ],
            "rubric": {
                "keywords": ["0.35", "usesTable", "FurnitureBuilder", "FigureBuilder", "Fallback", "giữa người và máy", "Z dương"],
                "criteria": [
                    "Giải thích hệ trục Z: người ở Z=0, camera ở Z=+distance, nên bàn ở Z=+0.35 mới nằm phía trước bụng người mẫu (giữa người và máy).",
                    "Chỉ ra nếu đặt Z âm, bàn sẽ lùi ra sau lưng người mẫu như thể người mẫu đang ngồi lên cạnh trước của bàn.",
                    "Phân tích cơ chế Graceful Fallback sang FigureBuilder: đảm bảo app không bao giờ trắng màn hình và mọi logic vật liệu/ánh sáng phía trên dùng chung một luồng."
                ]
            },
            "idealAnswer": "1. **Vị trí chiếc bàn ảo ở `z = +0.35`**:\n- Trong hệ quy chiếu của cảnh hướng dẫn, người mẫu 3D được căn tâm tại gốc $Z = 0$, còn camera hướng dẫn đứng ở $Z = +\\text{distance}$ nhìn về gốc toạ độ.\n- Trong thực tế chụp ảnh tại bàn cà phê, chiếc bàn luôn nằm **ở giữa người mẫu và máy ảnh** (người mẫu ngồi phía sau bàn, đặt tay lên mặt bàn phía trước ngực). Do đó, bàn phải có $Z > 0$ (`z = +0.35`). Nếu đặt $Z < 0$, chiếc bàn sẽ bị đẩy ra phía sau lưng người mẫu, gây sai lệch hoàn toàn phối cảnh che chắn.\n\n2. **Cơ chế Fallback về hình khối (`FigureBuilder.makeFigure`)**:\n- Khi phát triển thêm tư thế mới (chưa kịp nướng file `.usdz`) hoặc khi file asset bị lỗi nạp, `FigureAssetLoader.load` trả về `nil`. Thay vì làm sập cảnh hoặc để màn hình trống trơn, `GuideSceneBuilder` tự động dựng mô hình ma-nơ-canh từ các khối hình học cơ bản (`FigureBuilder`).\n- Việc gom điểm rẽ vào đúng 3 dòng `if let rigged ... else ...` giúp toàn bộ các bước phía sau (áp vật liệu mờ `FigureMaterial`, chiếu sáng 3 đèn `SceneLighting`, đặt góc máy `GuideCamera`) hoạt động hoàn toàn đồng nhất mà không cần biết mô hình bên dưới đến từ file USDZ hay hình khối."
        }
    ]


def get_architecture_and_code_questions():
    """Dạng 2: Kiến trúc và hàm cốt lõi (Giải thích sâu kiến trúc hệ thống và các hàm cốt lõi trong source code)."""
    return [
        {
            "id": "Q-ARCH-001",
            "title": "Kiến trúc Clean Architecture 3 tầng (`Cores` → `Domain` → `Features`) và thiết kế Pure Functions",
            "category": CAT_ARCH,
            "subCategory": "Kiến trúc hệ thống (System Architecture)",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/SceneComposer.swift", "NET_ver1/Domain/CaptureCheck.swift", "NET_ver1/Cores/FrameAnalyzer.swift"],
            "codeSnippet": "// Cấu trúc 3 tầng trong NET_ver1:\n// 1. Cores: CameraService, FrameAnalyzer (Đo đạc từ AVFoundation/Vision -> xuất CaptureMeasurements)\n// 2. Domain: SceneComposer, CaptureCheckEvaluator, PostureMatch, AutoCaptureDecider (Pure Functions, nonisolated)\n// 3. Features: CameraView, TranslucentSceneView, QualityCoachOverlay (SwiftUI + RealityKit)",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — Clean Architecture]\n\nDự án `NET_ver1` phân tách mã nguồn thành 3 tầng rõ rệt: `Cores` (Phần cứng & Đo đạc), `Domain` (Quy tắc nghiệp vụ nhiếp ảnh) và `Features` (Giao diện hiển thị 2D/3D).\n\n1. Tại sao `FrameAnalyzer` ở tầng `Cores` chỉ dừng lại ở việc tạo ra struct dữ liệu thuần `CaptureMeasurements` mà không trực tiếp đánh giá ảnh đạt hay trượt, nhường toàn bộ phần quyết định cho `CaptureCheckEvaluator`, `SceneComposer` và `PostureMatch` ở tầng `Domain`?\n2. Tại sao các struct ở tầng `Domain` đều được đánh dấu `nonisolated` và viết dưới dạng **Hàm thuần (Pure Functions)**? Điều này tác động thế nào đến tốc độ chạy Unit Test và khả năng chia sẻ dữ liệu đa luồng?",
            "hints": [
                "Tách biệt 'Đo đạc (Measurement)' cần CVPixelBuffer/Camera với 'Quyết định (Evaluation)' chỉ cần số học.",
                "Pure functions: cùng đầu vào luôn cho cùng đầu ra, không phụ thuộc trạng thái phần cứng.",
                "nonisolated giúp gọi hàm tự do từ cả background analysisQueue lẫn MainActor mà không tốn chi phí context switch."
            ],
            "rubric": {
                "keywords": ["Clean Architecture", "CaptureMeasurements", "Pure Functions", "nonisolated", "FrameAnalyzer", "CaptureCheckEvaluator", "SceneComposer", "Unit Test"],
                "criteria": [
                    "Phân tích ranh giới 'Chỉ đo, không quyết định' giữa FrameAnalyzer (Cores) và CaptureCheckEvaluator/SceneComposer (Domain).",
                    "Giải thích lợi ích của Pure Functions: tính tất định (deterministic), test hàng trăm kịch bản trong vài mili-giây không cần camera hay giả lập CVPixelBuffer.",
                    "Giải thích vai trò của từ khoá nonisolated trong Swift Concurrency: cho phép các kiểu dữ liệu và hàm thuần được gọi đồng bộ từ bất kỳ actor/queue nào."
                ]
            },
            "idealAnswer": "1. **Ranh giới 'Chỉ đo đạc, không quyết định' (`CaptureMeasurements`)**:\n- `FrameAnalyzer` phải làm việc trực tiếp với các đối tượng cấp thấp gắn chặt với phần cứng như `CVPixelBuffer`, `VNImageRequestHandler`, con trỏ bộ nhớ `UnsafePointer<UInt8>`. Nếu nhúng luôn logic nghiệp vụ nhiếp ảnh vào đây, ta sẽ không thể kiểm thử các quy tắc chấm điểm nếu không tạo ảnh giả lập phức tạp.\n- Do đó, `FrameAnalyzer` chỉ làm nhiệm vụ trích xuất các con số thô đã chuẩn hoá về hệ toạ độ `[0, 1]` và đóng gói vào `CaptureMeasurements` (một `Equatable` value type thuần tuý). Toàn bộ trí tuệ nhiếp ảnh nằm ở tầng `Domain` (`CaptureCheckEvaluator`, `SceneComposer`, `PostureMatch`).\n\n2. **Ý nghĩa của Pure Functions và `nonisolated`**:\n- **Kiểm thử tức thì (Zero-Hardware Testing)**: Vì các hàm ở `Domain` là hàm thuần (không đọc biến toàn cục, không chạm UI hay camera), bộ Unit Test (`SceneComposerTests`, `CaptureCheckTests`, `AutoCaptureTests`) chỉ cần khởi tạo struct `CaptureMeasurements` với vài con số là kiểm tra được mọi trường hợp biên trong vài mili-giây.\n- **Hiệu năng Concurrency với `nonisolated`**: Trong môi trường Swift Strict Concurrency, việc đánh dấu các struct và hàm thuần là `nonisolated` giúp chúng không bị trói buộc vào `@MainActor`. Nhờ đó, cả `analysisQueue` ở tầng nền lẫn `CameraView` trên Main Thread đều gọi được các hàm tính toán bố cục trực tiếp mà không tốn chi phí nhảy luồng (`await`)."
        },
        {
            "id": "Q-ARCH-002",
            "title": "Hàm cốt lõi `FrameAnalyzer.analyze`: Tối ưu hiệu năng gộp Vision Requests và lấy mẫu bước nhảy `step = 4` trên plane Y",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi tầng Cores & Tối ưu hiệu năng",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Cores/FrameAnalyzer.swift"],
            "codeSnippet": "// Trong FrameAnalyzer.swift:\nvar requests: [VNRequest] = [faceRequest, landmarkRequest, horizonRequest, poseRequest]\nif wantsSegmentation { requests.append(segmentationRequest) }\nlet handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)\ntry? handler.perform(requests)\n\n// Trong analyzeLuminance & sharpness:\nlet luma = base.assumingMemoryBound(to: UInt8.self)\nlet step = 4 // Bước 4 px theo cả X và Y",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `FrameAnalyzer.analyze`]\n\nMỗi khung hình từ camera cần phải trải qua hàng loạt phép đo: tìm mặt, tìm mí mắt, đo góc nghiêng đường chân trời, tìm 14 khớp xương cơ thể, tách nền, đo độ cháy sáng/chìm tối và tính độ sắc nét.\n\n1. Tại sao trong `runVision`, việc gom tất cả các `VNRequest` vào một mảng và gọi `handler.perform(requests)` **một lần duy nhất** lại tạo ra khác biệt lớn về hiệu năng so với gọi `perform` tuần tự từng request?\n2. Giải thích cách hai hàm cốt lõi `analyzeLuminance(_:)` và `sharpness(_:)` truy cập trực tiếp vào plane 0 (kênh Y - Luminance) của `CVPixelBuffer` với bước nhảy `step = 4` để giảm khối lượng tính toán đi 16 lần mà vẫn giữ độ chính xác.",
            "hints": [
                "VNImageRequestHandler.perform giải mã, xoay ảnh và nạp lên GPU/ANE một lần dùng chung cho cả batch request.",
                "Định dạng video camera là YCbCr (Bi-Planar), plane 0 chứa sẵn độ chói Y (UInt8 0..255) không cần đổi từ RGB.",
                "Lấy mẫu lưới 4x4 (step=4 theo cả chiều ngang và chiều dọc) giảm 4 * 4 = 16 lần số pixel phải duyệt."
            ],
            "rubric": {
                "keywords": ["VNImageRequestHandler", "perform", "CVPixelBufferLockBaseAddress", "luma", "step = 4", "16 lần", "sharpness", "gradient"],
                "criteria": [
                    "Giải thích lợi ích của batching trong handler.perform(requests): dùng chung một lần decode/xoay buffer và tối ưu lập lịch trên Neural Engine.",
                    "Giải thích cách đọc trực tiếp plane Y (Luminance) qua CVPixelBufferGetBaseAddress và assumingMemoryBound(to: UInt8.self).",
                    "Phân tích bước nhảy step = 4 trên cả 2 trục X, Y giúp giảm 16 lần số vòng lặp khi tính overexposed/underexposed và tổng gradient độ nét."
                ]
            },
            "idealAnswer": "1. **Gộp Batch Vision Requests trong một lần `handler.perform(requests)`**:\n- Khi truyền mảng 4–5 requests vào một lệnh `handler.perform(requests)` duy nhất, Vision Framework chỉ thực hiện giải mã (decode), chuẩn hoá hướng xoay (`orientation`) và truyền dữ liệu ảnh lên GPU / Apple Neural Engine (ANE) **đúng 1 lần**, sau đó chia sẻ các tầng đặc trưng trung gian giữa các mạng học sâu.\n- Ngoài ra, tham số `wantsBackgroundAnalysis` cho phép bật/tắt linh hoạt `VNGeneratePersonSegmentationRequest` (vốn tốn tài nguyên nhất) tuỳ theo chế độ chụp.\n\n2. **Kỹ thuật đọc trực tiếp Plane Y và giảm 16 lần chi phí với `step = 4`**:\n- Camera iOS xuất buffer định dạng YCbCr, trong đó plane đầu tiên chính là kênh độ chói **Y (Luminance)** với mỗi byte `UInt8` biểu diễn độ sáng từ `0` đến `255`. Hàm khoá bộ nhớ bằng `CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)` để đọc thẳng mảng byte mà không tốn chi phí khởi tạo `CIImage` hay chuyển đổi hệ màu RGB.\n- Với ảnh Full HD ($1920 \\times 1080 \\approx 2$ triệu điểm ảnh), duyệt từng pixel trên CPU sẽ gây nghẽn cổ chai. Việc nhảy bước `step = 4` trên cả trục $X$ và trục $Y$ chỉ lấy mẫu 1 điểm trong mỗi ô $4 \\times 4$, giảm khối lượng tính toán đi $4 \\times 4 = 16$ lần.\n- Hàm `sharpness` tận dụng chính bước nhảy này để tính tổng độ chênh lệch độ sáng (gradient bậc nhất) theo phương ngang `abs(center - luma[row + x + step])` và phương dọc `abs(center - luma[rowDown + x])` — ảnh càng sắc nét thì biến thiên biên độ giữa các điểm ảnh lân cận càng cao."
        },
        {
            "id": "Q-ARCH-003",
            "title": "Hàm cốt lõi `FigureAssetLoader.measureFigureHeight` & `wrapScaled`: Đo lưới `ModelComponent` và bọc Wrapper Entity",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi 3D RealityKit & OpenUSD",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/FigureAssetLoader.swift", "Tests/NET_ver1Tests/FigureAssetTests.swift"],
            "codeSnippet": "// Trong FigureAssetLoader.swift:\n@MainActor\nstatic func measureFigureHeight(_ entity: Entity) -> Float? {\n    var meshes = 0\n    var lowest = Float.greatestFiniteMagnitude\n    var highest = -Float.greatestFiniteMagnitude\n    func visit(_ node: Entity) {\n        if node.components[ModelComponent.self] != nil {\n            meshes += 1\n            let box = node.visualBounds(relativeTo: nil)\n            lowest = min(lowest, box.min.y)\n            highest = max(highest, box.max.y)\n        }\n        for child in node.children { visit(child) }\n    }\n    visit(entity)\n    guard meshes > 0, highest > lowest else { return nil }\n    return highest - lowest\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `FigureAssetLoader`]\n\nHai hàm `measureFigureHeight(_:)` và `wrapScaled(_:to:)` là trái tim của tầng nạp mô hình 3D trong `FigureAssetLoader.swift`.\n\n1. Tại sao hàm `measureFigureHeight` phải duyệt đệ quy cây entity để chỉ gọi `visualBounds(relativeTo: nil)` trên các node mang `ModelComponent` thay vì gọi một lần trên `entity` gốc?\n2. Phân tích toàn bộ quy trình trong `wrapScaled(_:to:)`: Tại sao phải tính `uniformScale = wantedHeight / referenceModelHeight` (dùng chiều cao chuẩn của tư thế đứng `1.798m`), bọc vào `wrapper = Entity()`, rồi cuối cùng lại phải trừ `wrapper.position.y -= lowestPoint`?",
            "hints": [
                "Entity gốc chứa các prim Xform trung gian từ Blender làm sai lệch kích thước bao (ra 1.70 x 1.18 x 2.88m).",
                "relativeTo: nil đo trong không gian thế giới (world space) để tính cả phép scale của node cha.",
                "Trừ lowestPoint đảm bảo bàn chân (hoặc điểm thấp nhất của tư thế) luôn chạm mặt đất Y = 0 sau khi scale."
            ],
            "rubric": {
                "keywords": ["ModelComponent", "visualBounds", "relativeTo: nil", "wrapScaled", "referenceModelHeight", "uniformScale", "lowestY", "wrapper"],
                "criteria": [
                    "Giải thích lý do lọc node có ModelComponent và truyền relativeTo: nil (bỏ qua Xform prim dư thừa, bảo toàn hiệu lực của scale trong hệ toạ độ thế giới).",
                    "Giải thích công thức uniformScale = (headHeight * 7.5) / referenceModelHeight: dùng một hệ số co giãn đồng nhất cho cả 6 tư thế để dáng ngồi tự động thấp hơn dáng đứng.",
                    "Giải thích bước bọc trong wrapper Entity() và dịch chuyển wrapper.position.y -= lowestPoint để đặt mô hình tiếp đất tại Y = 0."
                ]
            },
            "idealAnswer": "1. **Cơ chế của `measureFigureHeight(_:)`**:\n- **Chỉ đo trên node có `ModelComponent`**: File USDZ xuất từ Blender có cây phân cấp gồm nhiều node `Xform` cha mang transform dư thừa. Nếu gọi `visualBounds` trên root entity, kết quả đo bị phình ảo (`1.70 × 1.18 × 2.88m` thay vì kích thước thật của lưới da `1.33 × 0.54 × 0.79m`). Duyệt tìm đúng các node chứa `ModelComponent` đảm bảo chỉ đo hình học thực tế của cơ thể.\n- **Truyền `relativeTo: nil`**: Nếu truyền `relativeTo: entity`, RealityKit đo trong hệ toạ độ nội bộ của chính entity đó nên bỏ qua hoàn toàn thuộc tính `scale`. Truyền `nil` buộc phép đo thực hiện trong World Space, phản ánh chính xác kích thước sau khi phóng to/thu nhỏ.\n\n2. **Quy trình 3 bước trong hàm cốt lõi `wrapScaled(_:to:)`**:\n- **Bước 1 — Tính `uniformScale` đồng nhất**: Lấy chiều cao mong muốn của người mẫu `wantedHeight = headHeight * 7.5` chia cho chiều cao chuẩn của mô hình đứng `referenceModelHeight (1.798m)`. Việc dùng chung một mẫu số duy nhất cho cả 6 tư thế giúp giữ nguyên tỉ lệ tự nhiên giữa đứng và ngồi (người ngồi `1.331m` sẽ tự động cao `1.258m`, thấp hơn người đứng `1.70m`).\n- **Bước 2 — Bọc trong `wrapper = Entity()`**: Gán `scale` trực tiếp lên root entity nạp từ USDZ bị RealityKit bỏ qua. Bọc nó vào một `Entity` cha rỗng rồi gán `wrapper.scale = SIMD3(repeating: uniformScale)` là cách duy nhất đảm bảo phép biến đổi có hiệu lực.\n- **Bước 3 — Đặt chân chạm đất (`wrapper.position.y -= lowestPoint`)**: Sau khi scale, điểm thấp nhất của mô hình có thể bị trôi lệch khỏi mặt phẳng $Y = 0$. Hàm gọi `lowestY(wrapper)` để đo điểm thấp nhất thực tế rồi dịch chuyển `wrapper.position.y` để gót chân luôn đặt chuẩn xác trên mặt sàn."
        },
        {
            "id": "Q-ARCH-004",
            "title": "Kiến trúc Dual-Engine (`RealityView` iOS 18 vs `ARView` iOS 17) và hàm `GuideCamera.position` / `GuideCamera.target`",
            "category": CAT_ARCH,
            "subCategory": "Kiến trúc hiển thị 3D & Camera Toán học",
            "difficulty": "Lead",
            "relatedFiles": ["NET_ver1/Features/TranslucentSceneView.swift"],
            "codeSnippet": "// Trong GuideCamera (TranslucentSceneView.swift):\nstatic func position(for pose: ShootingPose) -> SIMD3<Float> {\n    let distance = pose.cameraDistance\n    let visibleHeight = 2 * distance * tan(Double.pi / 6)\n    let frameCenterY = visibleHeight / 2\n    return SIMD3<Float>(0, Float(frameCenterY), Float(distance))\n}\n\nstatic func target(for pose: ShootingPose) -> Entity {\n    let distance = pose.cameraDistance\n    let visibleHeight = 2 * distance * tan(Double.pi / 6)\n    let target = Entity()\n    target.position = SIMD3<Float>(0, Float(visibleHeight / 2), 0)\n    return target\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `TranslucentSceneView` & `GuideCamera`]\n\nTrong `TranslucentSceneView.swift`, ứng dụng hỗ trợ đồng thời hai thế hệ API dựng cảnh 3D của Apple: `RealityView` (iOS 18+) và `ARView` (iOS 17).\n\n1. Hãy giải thích công thức lượng giác `visibleHeight = 2 * distance * tan(Double.pi / 6)` trong `GuideCamera`: Tại sao góc là $\\pi / 6$ ($30^\\circ$), tại sao cao độ camera phải đặt ở `visibleHeight / 2`, và tại sao toạ độ Z của camera phải là `+distance` (dương)?\n2. Tại sao `GuideCamera` phải được tách thành một `enum` riêng bên ngoài `TranslucentSceneView<Content: View>`? Và trong nhánh iOS 17 (`TranslucentARViewRepresentable`), tại sao lớp `Coordinator` phải giữ tham chiếu tường minh tới `var root: Entity?` và `var camera: PerspectiveCamera?`?",
            "hints": [
                "Vertical FOV của camera là 60 độ (pi/3), nên nửa góc mở trên/dưới là 30 độ (pi/6).",
                "Swift không cho phép kiểu generic struct TranslucentSceneView<Content: View> chứa static stored property, và tách GuideCamera giúp Unit Test gọi trực tiếp công thức thật.",
                "ARView.scene.anchors trả về kiểu giao thức HasAnchoring (mỗi lần đọc là một Any khác nhau), nên Coordinator phải giữ tham chiếu trực tiếp tới root entity để updateUIView đổi màu vật liệu."
            ],
            "rubric": {
                "keywords": ["GuideCamera", "visibleHeight", "tan(Double.pi / 6)", "FOV", "cameraTarget", "Coordinator", "HasAnchoring", "generic"],
                "criteria": [
                    "Chứng minh công thức hình học: với FOV dọc = 60° (nửa góc = 30° = pi/6), chiều cao vùng nhìn thấy tại khoảng cách d là 2 * d * tan(30°), tâm khung nằm ở visibleHeight / 2.",
                    "Giải thích 2 lý do tách enum GuideCamera: giới hạn của generic type trong Swift và đảm bảo Single Source of Truth giữa code app với Unit Test.",
                    "Giải thích vai trò của Coordinator trong TranslucentARViewRepresentable: giữ tham chiếu trực tiếp tới root Entity để updateUIView cập nhật FigureMaterial mà không phải duyệt lại ARView.scene.anchors."
                ]
            },
            "idealAnswer": "1. **Toán học của `GuideCamera.position(for:)` và `GuideCamera.target(for:)`**:\n- **Công thức `visibleHeight = 2 * distance * tan(Double.pi / 6)`**: Camera hướng dẫn sử dụng góc mở dọc (Vertical FOV) là $60^\\circ$ ($\\pi / 3$ rad). Xét tam giác vuông tạo bởi trục quang học và tia biên trên/dưới (nửa góc mở là $30^\\circ = \\pi / 6$ rad), nửa chiều cao khung nhìn tại khoảng cách `distance` là $\\text{distance} \\times \\tan(\\pi / 6)$. Do đó tổng chiều cao khung nhìn là $2 \\times \\text{distance} \\times \\tan(\\pi / 6)$.\n- **Cao độ `frameCenterY = visibleHeight / 2`**: Vì bàn chân người mẫu đứng tại mặt đất $Y = 0$, việc đặt tâm camera ở đúng nửa chiều cao khung nhìn giúp khung hình bắt đầu vừa khít từ $Y = 0$ lên tới $Y = \\text{visibleHeight}$, không bao giờ cắt mất chân người mẫu.\n- **Trục `Z = +distance`**: Người mẫu đứng ở gốc $(0, 0, 0)$ mặt hướng về $+Z$, nên camera phải lùi về phía $+Z$ và nhìn ngược về gốc toạ độ.\n\n2. **Lý do tách `enum GuideCamera` và dùng `Coordinator` trong `TranslucentARViewRepresentable`**:\n- **Tách `GuideCamera`**: Thứ nhất, `TranslucentSceneView<Content: View>` là một kiểu generic nên trình biên dịch Swift cấm khai báo `static let entityName` bên trong nó. Thứ hai, đặt công thức toạ độ ở một enum `internal` độc lập giúp bộ Unit Test gọi trực tiếp chính hàm của app thay vì copy-paste lại công thức vào file test (tránh rủi ro test xanh giả tạo khi công thức trong view thay đổi).\n- **Vai trò của `Coordinator`**: Trong UIKit/RealityKit, `ARView.scene.anchors` trả về tập hợp kiểu `HasAnchoring` bị xoá kiểu (type-erased) và không có thuộc tính `.entity` trực tiếp. Lưu giữ `var root: Entity?` trong `Coordinator` giúp hàm `updateUIView` cập nhật màu sắc vật liệu (`FigureMaterial.apply(to: root, isAligned: isAligned)`) ngay lập tức mỗi khi trạng thái khớp tư thế thay đổi trên SwiftUI."
        },
        {
            "id": "Q-ARCH-005",
            "title": "Hàm cốt lõi `PostureMatch.evaluate` và `CaptureCheckEvaluator.checkHeadScale`: Định nghĩa `isAligned` và quy đổi tỉ lệ mặt/đầu",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi tầng Domain & Nhân trắc học",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/PostureMatch.swift", "NET_ver1/Domain/CaptureCheck.swift"],
            "codeSnippet": "// Trong PostureMatch.swift:\nvar isAligned: Bool { adjustment == .none }\n\n// Trong CaptureCheck.swift:\nprivate static func checkHeadScale(faceHeight: CGFloat, template: PoseTemplate) -> CriterionResult {\n    let faceToHeadRatio: CGFloat = 0.75\n    let actualHeadHeight = faceHeight / faceToHeadRatio\n    if actualHeadHeight < QualityThresholds.minimumHeadHeightRatio { ... }\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `PostureMatch` & `checkHeadScale`]\n\n1. Trong `PostureMatch.swift`, tại sao thuộc tính quyết định tư thế đã khớp lại được viết là `var isAligned: Bool { adjustment == .none }` mà nghiêm cấm dùng `score >= idealThreshold` để thay thế? Vai trò của biến `score` khác với `isAligned` như thế nào?\n2. Trong hàm `CaptureCheckEvaluator.checkHeadScale(faceHeight:template:)`, tại sao phải chia `faceHeight` của Vision cho hằng số `faceToHeadRatio = 0.75` trước khi so sánh với chiều cao đầu của khuôn mẫu? Chuyện gì xảy ra nếu so sánh trực tiếp `rect.height` của Vision với chiều cao đầu hoặc chiều cao thân?",
            "hints": [
                "Nếu dùng score >= idealThreshold, khi chỉnh ngưỡng hiển thị thanh tiến độ sẽ vô tình làm AutoCapture bấm chụp lúc UI vẫn hiện mũi tên báo lệch.",
                "VNFaceObservation chỉ trả về khung bao từ chân tóc (trán) tới cằm, thiếu mất 25% phần hộp sọ và tóc trên đỉnh đầu.",
                "So sánh trực tiếp mà không chia 0.75 sẽ bắt người mẫu phải tiến lại gần ống kính hơn 33% so với thiết kế."
            ],
            "rubric": {
                "keywords": ["isAligned", "adjustment == .none", "idealThreshold", "score", "checkHeadScale", "faceToHeadRatio", "0.75", "chân tóc"],
                "criteria": [
                    "Giải thích sự tách biệt trách nhiệm giữa isAligned (điều kiện logic: không còn bất kỳ adjustment nào) và score (chỉ dùng để vẽ thanh tiến độ UI).",
                    "Chỉ ra rủi ro bất đồng bộ nếu dùng score >= idealThreshold: AutoCapture có thể bấm chụp trong khi màn hình vẫn đang hiện mũi tên nhắc dịch chuyển.",
                    "Giải thích hằng số sinh học faceToHeadRatio = 0.75: bbox khuôn mặt của Vision chỉ đo từ lông mày/trán tới cằm (bằng 3/4 toàn bộ đầu tính cả đỉnh sọ và tóc)."
                ]
            },
            "idealAnswer": "1. **Tại sao `isAligned` bắt buộc là `adjustment == .none` thay vì `score >= idealThreshold`**:\n- Trong kiến trúc của `PostureMatch`, `adjustment` là nguồn sự thật duy nhất (Single Source of Truth) cho biết người mẫu còn lỗi tư thế nào cần sửa hay không (`.moveLeft`, `.tooClose`, `.pose`, hoặc `.none`).\n- Trong khi đó, `score` (`0...1`) chỉ là con số định lượng phục vụ cho việc **vẽ thanh tiến độ hiển thị (UI progress)**. Nếu định nghĩa `isAligned` dựa trên `score >= idealThreshold`, một lập trình viên sau này chỉnh sửa hệ số tính điểm hoặc đổi ngưỡng `idealThreshold` sẽ gây ra lỗi nghịch lý: màn hình vẫn đang hiện mũi tên bắt người mẫu bước sang trái (`adjustment != .none`) nhưng bộ chụp tự động `AutoCaptureDecider` đã tưởng là khớp và bấm chụp.\n\n2. **Cơ chế quy đổi `faceToHeadRatio = 0.75` trong `checkHeadScale`**:\n- Thứ nhất, ở chế độ chụp người, `subjectRect` lấy từ `VNFaceObservation` chỉ là **bounding box của khuôn mặt**, không phải toàn thân. Nếu đem so với chiều cao thân, app sẽ bắt người mẫu dí sát mặt vào camera.\n- Thứ hai, ngay cả khi so với chiều cao đầu (`headHeightRatio`), thuật toán nhận diện mặt của Apple Vision chỉ đóng khung từ vùng trán/chân mày xuống tới cằm — bỏ qua hoàn toàn phần hộp sọ trên và mái tóc (chiếm khoảng 25% tổng chiều cao đầu). Do đó `faceHeight` thực chất chỉ bằng `0.75` lần chiều cao đầu thật. Phép chia `actualHeadHeight = faceHeight / 0.75` khôi phục lại kích thước đầu chuẩn theo nhân trắc học (`BodyCanon`) trước khi kiểm tra với ngưỡng `[0.11, 0.26]`."
        },
        {
            "id": "Q-ARCH-006",
            "title": "Hàm cốt lõi `SafeArea.init` và `viewPoint`/`viewRect`: Biến đổi hệ quy chiếu giữa Vision (Đáy-Trái) và View (Trên-Trái)",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi Toán học & Hệ toạ độ",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Domain/SafeArea.swift", "Tests/NET_ver1Tests/SafeAreaTests.swift"],
            "codeSnippet": "// Trong SafeArea.swift:\nfunc viewPoint(fromVisionPoint point: CGPoint) -> CGPoint {\n    let x = (point.x - horizontalCrop) / visibleWidthRatio\n    let yFromBottom = (point.y - verticalCrop) / visibleHeightRatio\n    return CGPoint(x: x, y: 1 - yFromBottom)\n}\n\nfunc viewRect(fromVisionRect rect: CGRect) -> CGRect {\n    let x = (rect.minX - horizontalCrop) / visibleWidthRatio\n    let width = rect.width / visibleWidthRatio\n    let topFromBottom = rect.minY + rect.height\n    let top = 1 - (topFromBottom - verticalCrop) / visibleHeightRatio\n    return CGRect(x: x, y: top, width: width, height: rect.height / visibleHeightRatio)\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `SafeArea`]\n\nLớp `SafeArea` chịu trách nhiệm chuyển đổi mọi toạ độ điểm và hình chữ nhật từ Apple Vision sang hệ toạ độ khung hiển thị SwiftUI.\n\n1. Hãy phân tích hai sự khác biệt cốt lõi giữa hệ toạ độ của Vision và hệ toạ độ của View mà `SafeArea` phải giải quyết (về vùng cắt `.resizeAspectFill` và về hướng trục Y).\n2. Trong hàm `viewRect(fromVisionRect:)`, tại sao để tìm toạ độ `y` (cạnh trên) của hình chữ nhật trên View, ta bắt buộc phải tính `let topFromBottom = rect.minY + rect.height` trước rồi mới lấy `1 - ...`, thay vì chỉ lật trực tiếp `rect.minY` như ở hàm `viewPoint`?",
            "hints": [
                "Vision có gốc (0,0) ở Đáy-Trái (trục Y hướng lên), còn SwiftUI/UIKit có gốc (0,0) ở Trên-Trái (trục Y hướng xuống).",
                "Đối với một hình chữ nhật trong hệ Đáy-Trái, rect.minY là cạnh DƯỚI của hình chữ nhật, còn cạnh TRÊN là rect.minY + rect.height.",
                "Khi lật trục Y sang hệ Trên-Trái, cạnh trên của hình chữ nhật mới chính là gốc origin.y của CGRect mới."
            ],
            "rubric": {
                "keywords": ["SafeArea", "viewPoint", "viewRect", "horizontalCrop", "visibleWidthRatio", "đáy-trái", "trên-trái", "topFromBottom", "rect.minY + rect.height"],
                "criteria": [
                    "Nêu rõ 2 phép biến đổi: (1) Tịnh tiến và co giãn theo vùng ảnh còn lại sau khi bị cắt bởi resizeAspectFill, (2) Đảo chiều trục Y từ gốc Đáy-Trái sang Trên-Trái.",
                    "Chứng minh hình học trong viewRect: trong hệ Vision (Y hướng lên), rect.minY là đáy dưới của hộp, còn đỉnh trên của hộp nằm tại rect.minY + rect.height.",
                    "Giải thích nếu chỉ lấy 1 - rect.minY làm origin.y mới, toàn bộ hình chữ nhật sẽ bị dịch lệch xuống dưới một đoạn đúng bằng chiều cao rect.height của chính nó."
                ]
            },
            "idealAnswer": "1. **Hai sự khác biệt hệ quy chiếu mà `SafeArea` giải quyết**:\n- **Khác biệt về vùng phủ (Crop do `.resizeAspectFill`)**: Vision chuẩn hoá `[0, 1]` trên toàn bộ buffer gốc của cảm biến, nhưng màn hình chỉ hiển thị phần giữa sau khi đã cắt đi `horizontalCrop` ở mỗi bên trái/phải (hoặc `verticalCrop` ở trên/dưới). Do đó phải trừ đi phần rìa bị cắt và chia lại cho tỉ lệ vùng nhìn thấy `visibleWidthRatio = 1 - horizontalCrop * 2`.\n- **Khác biệt về hướng trục dọc ($Y$)**: Vision dùng hệ toạ độ toán học/OpenGL với gốc $(0, 0)$ ở **Đáy-Trái** (trục $Y$ hướng từ dưới lên trên). Ngược lại, SwiftUI/UIKit dùng gốc $(0, 0)$ ở **Trên-Trái** (trục $Y$ hướng từ trên xuống dưới).\n\n2. **Tại sao `viewRect` phải tính `topFromBottom = rect.minY + rect.height`**:\n- Đối với một điểm đơn lẻ (`viewPoint`), việc lật trục chỉ đơn giản là $Y_{\\text{view}} = 1 - Y_{\\text{bottom}}$.\n- Nhưng đối với một hình chữ nhật (`CGRect`), `origin.y` luôn đại diện cho cạnh có giá trị $Y$ nhỏ nhất trong hệ toạ độ đó. Trong hệ Vision (gốc ở đáy), `rect.minY` là **cạnh đáy dưới** của hình chữ nhật, còn **cạnh đỉnh trên** của nó nằm ở vị trí `rect.minY + rect.height`.\n- Khi chuyển sang hệ View (gốc ở đỉnh màn hình), `origin.y` của `CGRect` mới phải là **cạnh đỉnh trên** của hình chữ nhật. Vì vậy ta bắt buộc phải lấy toạ độ đỉnh trên `topFromBottom = rect.minY + rect.height` rồi mới lấy `1 - (topFromBottom - verticalCrop) / visibleHeightRatio`. Nếu lật trực tiếp `rect.minY`, hình chữ nhật trên màn hình sẽ bị tụt xuống dưới một đoạn đúng bằng chiều cao của chính nó!"
        },
        {
            "id": "Q-ARCH-007",
            "title": "Hàm cốt lõi `CameraService.setZoom` và `AnalysisConfigurationStore`: Quản lý phần cứng & Đồng bộ luồng an toàn",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi Concurrency & AVFoundation",
            "difficulty": "Senior",
            "relatedFiles": ["NET_ver1/Cores/CameraService.swift", "NET_ver1/Cores/AnalysisConfiguration.swift"],
            "codeSnippet": "// Trong CameraService.swift:\nfunc setZoom(_ factor: CGFloat, animated: Bool = false) {\n    sessionQueue.async { [weak self] in\n        // lockForConfiguration()\n        if animated {\n            device.ramp(toVideoZoomFactor: target, withRate: 4)\n        } else {\n            device.videoZoomFactor = target\n        }\n        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }\n    }\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `CameraService` & `AnalysisConfigurationStore`]\n\nTầng `Cores` vận hành song song nhiều hàng đợi: `@MainActor` (UI), `sessionQueue` (điều khiển phần cứng `AVCaptureSession`/`AVCaptureDevice`) và `analysisQueue` (xử lý hình ảnh Vision mỗi frame).\n\n1. Giải thích thiết kế của `AnalysisConfigurationStore`: Làm thế nào store này cho phép `MainActor` ghi cấu hình (`mode`, `viewportSize`) và `analysisQueue` đọc cấu hình đồng bộ ở tốc độ 30–60fps mà không vi phạm Swift 6 Strict Concurrency và không làm nghẽn Main Thread?\n2. Trong hàm `CameraService.setZoom(_:animated:)`, tại sao mọi thao tác chạm vào `AVCaptureDevice` phải đẩy vào `sessionQueue.async`, bắt buộc gọi `lockForConfiguration()`, và khi nào dùng `animated = false` (nhảy thẳng) so với `animated = true` (`device.ramp`)?",
            "hints": [
                "AnalysisConfigurationStore dùng NSLock bảo vệ vùng nhớ cấu hình, thời gian giữ lock chỉ vài nano-giây.",
                "AVCaptureDevice ném NSGenericException nếu sửa videoZoomFactor mà không gọi lockForConfiguration().",
                "Đổi tư thế tự động dùng animated=false để tránh trễ khung hình; người dùng vuốt zoom dùng ramp(withRate: 4) để mượt mắt."
            ],
            "rubric": {
                "keywords": ["AnalysisConfigurationStore", "NSLock", "sessionQueue", "analysisQueue", "lockForConfiguration", "videoZoomFactor", "ramp", "smoothAutoFocus"],
                "criteria": [
                    "Phân tích kiến trúc đồng bộ giữa MainActor và analysisQueue thông qua AnalysisConfigurationStore dùng NSLock.",
                    "Giải thích quy tắc AVFoundation: điều khiển phần cứng trên serial sessionQueue để không làm đơ UI và bắt buộc gọi lockForConfiguration().",
                    "Phân biệt rõ chiến lược animated=false (nhảy tức thì khi tự động lấy góc) và animated=true (ramp mượt khi vuốt tay) kèm smoothAutoFocusEnabled."
                ]
            },
            "idealAnswer": "1. **Kiến trúc truyền cấu hình không khoá luồng UI (`AnalysisConfigurationStore`)**:\n- `CameraView` và các thuộc tính `@Published` của `CameraService` nằm trên `@MainActor`, trong khi callback nhận frame video chạy trên `analysisQueue` nền. Nếu dùng `MainActor.assumeIsolated` sẽ gây crash runtime, còn nếu dùng `await MainActor.run` thì hàng đợi phân tích ảnh phải dừng chờ Main Thread ở mỗi frame, gây tụt FPS.\n- `AnalysisConfigurationStore` giải quyết bằng cách đóng gói các thông số cấu hình (`CaptureMode`, kích thước khung...) vào một đối tượng độc lập được bảo vệ bởi `NSLock`. Khi người dùng đổi mode trên UI, MainActor cập nhật bản snapshot vào Store; khi `analysisQueue` xử lý frame, nó đọc bản snapshot này đồng bộ trong tích tắc mà hoàn toàn độc lập với MainActor.\n\n2. **Thiết kế hàm cốt lõi `CameraService.setZoom(_:animated:)`**:\n- **Chạy trên `sessionQueue` & `lockForConfiguration()`**: Các lời gọi phần cứng của `AVCaptureDevice` có thể tốn thời gian phần cứng và sẽ ném ngoại lệ `NSGenericException` nếu thay đổi `videoZoomFactor` mà chưa nắm giữ khoá độc quyền `try device.lockForConfiguration()`.\n- **Phân biệt `animated = false` vs `device.ramp`**: Khi người dùng bấm nút *'Lấy góc này'* hoặc khi đổi tư thế, app gọi `setZoom(layout.suggestedZoom, animated: false)` để ống kính nhảy tới tiêu cự mục tiêu ngay lập tức, giúp thuật toán chấm tư thế ổn định ngay. Khi có thao tác vuốt zoom liên tục, `animated = true` kích hoạt `device.ramp(toVideoZoomFactor:withRate: 4)` kết hợp `smoothAutoFocusEnabled = true` để tiêu cự và điểm lấy nét trượt êm không bị giật."
        },
        {
            "id": "Q-ARCH-008",
            "title": "Hàm cốt lõi `AutoCaptureDecider.evaluate`: Thiết kế State Machine với `ContinuousClock` và cửa sổ giữ yên 1.2 giây",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi State Machine & Thời gian thực",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Domain/AutoCapture.swift", "NET_ver1/Features/CameraView.swift"],
            "codeSnippet": "// Trong AutoCapture.swift:\npublic struct AutoCaptureDecider {\n    public static let requiredStillness: Duration = .seconds(1.2)\n    public mutating func evaluate(\n        now: ContinuousClock.Instant,\n        match: PostureMatch,\n        eyesOpen: Bool,\n        headMoved: Bool\n    ) -> Decision\n}",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `AutoCaptureDecider`]\n\n1. Tại sao hàm `AutoCaptureDecider.evaluate` lại nhận thời điểm hiện tại `now: ContinuousClock.Instant` làm tham số truyền vào từ bên ngoài (Dependency Injection) thay vì tự gọi `Date()` hay `ContinuousClock().now` bên trong thân hàm?\n2. Phân tích máy trạng thái (State Machine) bên trong `AutoCaptureDecider` và hàm `CameraView.evaluateAutoCapture`: Các trạng thái `.waiting`, `.nearlyReady(progress)` và `.capture` chuyển đổi ra sao khi một trong 3 điều kiện (`match.isAligned`, `eyesOpen`, `!headMoved`) bị vi phạm giữa chừng?",
            "hints": [
                "Truyền now: ContinuousClock.Instant vào hàm giúp Unit Test giả lập thời gian trôi qua 0.5s, 1.0s, 1.2s ngay lập tức mà không cần dùng sleep() làm chậm bộ test.",
                "ContinuousClock là đồng hồ đơn điệu (monotonic), không bị nhảy sai nếu hệ thống đồng bộ giờ NTP.",
                "Chỉ cần 1 frame bị lệch tư thế, nhắm mắt hoặc lắc đầu (abs(head.x - last) > 0.05) là mốc thời gian bắt đầu giữ yên bị reset về 0 ngay lập tức."
            ],
            "rubric": {
                "keywords": ["AutoCaptureDecider", "ContinuousClock.Instant", "Dependency Injection", "1.2", "nearlyReady", "headMoved", "reset", "Unit Test"],
                "criteria": [
                    "Giải thích lợi ích kiến trúc khi truyền now: ContinuousClock.Instant làm tham số: hàm trở thành deterministic, Unit Test kiểm tra cửa sổ 1.2s trong 0.001ms mà không cần Thread.sleep.",
                    "Giải thích ưu điểm của ContinuousClock so với Date(): thời gian tăng đơn điệu, không bị ảnh hưởng bởi thay đổi múi giờ hay NTP.",
                    "Mô tả chính xác luồng chuyển trạng thái: tích luỹ progress từ 0 -> 1 trong 1.2s (.nearlyReady), đạt 1.2s thì phát .capture, và reset ngay lập tức về .waiting nếu bất kỳ điều kiện nào bị phá vỡ."
                ]
            },
            "idealAnswer": "1. **Thiết kế truyền `now: ContinuousClock.Instant` làm tham số (Time Injection)**:\n- **Kiểm thử tức thời không cần `sleep`**: Nếu bên trong hàm tự gọi `ContinuousClock().now`, để test cửa sổ giữ yên 1.2 giây cho 10 kịch bản khác nhau, bộ Unit Test sẽ phải `sleep(1.2)` mất hơn 12 giây thực tế và rất dễ bị flaky (chập chờn do tải CPU). Khi nhận `now` qua tham số, `AutoCaptureTests` chỉ cần truyền `t0`, `t0 + .milliseconds(600)`, `t0 + .milliseconds(1200)` để kiểm tra chính xác tuyệt đối mọi mốc thời gian trong chưa đầy 1 mili-giây.\n- **Tính đơn điệu của `ContinuousClock`**: Khác với `Date()` (có thể bị nhảy lùi hoặc tiến khi điện thoại đồng bộ giờ mạng NTP), `ContinuousClock` đo thời gian trôi qua một cách đơn điệu (monotonic), đảm bảo phép trừ khoảng thời gian luôn chính xác.\n\n2. **Cơ chế State Machine của `AutoCaptureDecider`**:\n- Ở mỗi frame, `CameraView` kiểm tra độ dịch chuyển ngang của đầu so với frame trước (`abs(head.x - last) > 0.05` $\\rightarrow$ `headMoved = true`).\n- Nếu cả 3 điều kiện cùng thoả mãn (`match.isAligned && eyesOpen && !headMoved`):\n  - Frame đầu tiên: Ghi nhận mốc bắt đầu `alignedSince = now` và trả về `.nearlyReady(progress: 0)`.\n  - Các frame tiếp theo: Tính tỉ lệ `progress = elapsed / 1.2s` để vẽ vòng tròn xanh `autoProgressRing` quanh đầu người 3D.\n  - Khi `elapsed >= 1.2s`: Trả về `.capture` để kích hoạt màn trập và gọi `reset()`.\n- Nếu ở bất kỳ thời điểm nào (dù đã đạt 1.1 giây) mà người mẫu chớp mắt, lắc đầu hoặc lệch khỏi khuôn, `alignedSince` lập tức bị xoá về `nil` và trả về `.waiting` (`autoProgress = 0`), buộc chu kỳ giữ yên 1.2s phải đếm lại từ đầu."
        },
        {
            "id": "Q-ARCH-009",
            "title": "Hàm cốt lõi `SceneLighting.make()` và `FigureMaterial.apply`: Kiến trúc chiếu sáng 3 điểm (Three-Point Lighting) và PBR Blending",
            "category": CAT_ARCH,
            "subCategory": "Hàm cốt lõi Đồ hoạ 3D & Shading",
            "difficulty": "Mid",
            "relatedFiles": ["NET_ver1/Features/TranslucentSceneView.swift", "NET_ver1/Domain/FigureMaterial.swift"],
            "codeSnippet": "// Trong TranslucentSceneView.swift (SceneLighting.make):\n// 1. key: intensity = 900, position = (-1.2, 1.9, 1.4)\n// 2. fill: intensity = 260, position = (1.4, 1.0, 0.8)\n// 3. rim: intensity = 1100, position = (0.5, 1.7, -1.6)\n\n// Trong FigureMaterial.swift:\nmaterial.baseColor = .init(tint: isAligned ? alignedTint : guidingTint)\nmaterial.blending = .transparent(opacity: .init(scale: Float(alpha)))",
            "question": "[Dạng câu hỏi: KIẾN TRÚC & HÀM CỐT LÕI — `SceneLighting` & `FigureMaterial`]\n\n1. Phân tích hàm `SceneLighting.make()` trong `TranslucentSceneView.swift`: Tại sao cảnh 3D hướng dẫn phải sử dụng kỹ thuật **Chiếu sáng 3 điểm (Key, Fill, Rim light)** với vị trí và cường độ khác nhau (`900`, `260`, `1100`) thay vì dùng một nguồn sáng duy nhất? Và tại sao `TranslucentSceneView` cung cấp hàm `static func makeTestLights() -> [Entity]`?\n2. Phân tích hàm `FigureMaterial.apply(to:isAligned:)`: Cách hàm áp dụng `PhysicallyBasedMaterial` với `.transparent` blending và thay đổi độ mờ (`alphaWhenGuiding = 0.40` sang `alphaWhenAligned = 0.18`) hoạt động như thế nào?",
            "hints": [
                "Vật liệu PBR không tự phát sáng; nếu chỉ có 1 đèn trước mặt thì hình khối bị bệt phẳng hoặc nửa sau tối đen.",
                "Rim light (cường độ 1100 đặt ở Z = -1.6 phía sau lưng người mẫu) tạo đường viền sáng tách bóng 3D khỏi nền video camera thực tế.",
                "makeTestLights() là cổng kiểm thử thu hẹp (test seam) cho phép Unit Test kiểm tra hệ thống đèn mà không cần phơi bày toàn bộ nội thất dựng cảnh."
            ],
            "rubric": {
                "keywords": ["SceneLighting", "key", "fill", "rim", "makeTestLights", "PhysicallyBasedMaterial", "transparent", "alphaWhenAligned", "alphaWhenGuiding"],
                "criteria": [
                    "Giải thích vai trò của 3 nguồn sáng studio: Key (tạo khối chính), Fill (nâng chi tiết vùng tối), Rim (đặt phía sau Z=-1.6 với cường độ cao nhất 1100 để tạo viền sáng tách chủ thể 3D khỏi nền camera).",
                    "Giải thích mẫu thiết kế makeTestLights(): mở một test seam nhỏ gọn để Unit Test kiểm chứng số lượng và cường độ đèn.",
                    "Giải thích cơ chế duyệt cây entity trong FigureMaterial.apply để gán vật liệu PBR bán trong suốt và giảm độ đậm từ 0.40 xuống 0.18 khi đã khớp tư thế."
                ]
            },
            "idealAnswer": "1. **Kiến trúc chiếu sáng Studio 3 điểm trong `SceneLighting.make()`**:\n- Vì mô hình sử dụng `PhysicallyBasedMaterial` (PBR), hình khối 3D hoàn toàn phụ thuộc vào phản xạ ánh sáng. Nếu không có đèn hoặc chỉ có 1 đèn chiếu thẳng, bề mặt người mẫu sẽ bệt màu như một miếng giấy 2D dán lên màn hình.\n- `SceneLighting.make()` thiết lập 3 nguồn `DirectionalLight` chuẩn studio:\n  - **Key Light (`intensity = 900`, `pos = (-1.2, 1.9, 1.4)`)**: Chiếu chéo từ phía trước trên cao xuống để tạo mảng sáng tối định hình cơ thể và khuôn mặt.\n  - **Fill Light (`intensity = 260`, `pos = (1.4, 1.0, 0.8)`)**: Chiếu nhẹ từ phía đối diện thấp hơn để làm dịu vùng bóng tối, giữ chi tiết các nếp gấp.\n  - **Rim Light (`intensity = 1100`, `pos = (0.5, 1.7, -1.6)`)**: Đặt **phía sau lưng** người mẫu ($Z = -1.6$) với cường độ mạnh nhất chiếu ngược về trước để tạo đường viền sáng (backlight/rim) giúp mắt người chụp tách biệt rõ ràng hình bóng 3D khỏi luồng video camera phức tạp phía dưới.\n- **Hàm `makeTestLights()`**: Đóng vai trò là một cổng kiểm thử (Test Seam) có kiểm soát, giúp Unit Test kiểm tra cảnh luôn có đủ đèn phát sáng mà không phá vỡ tính đóng gói.\n\n2. **Cơ chế `FigureMaterial.apply(to:isAligned:)`**:\n- Hàm duyệt đệ quy toàn bộ các node con trong cây `Entity`, tìm mọi `ModelComponent` và thay thế mảng `materials` bằng một `PhysicallyBasedMaterial` có `blending = .transparent(opacity: .init(scale: Float(alpha)))`.\n- Khi `isAligned == false` (đang hướng dẫn): dùng màu cam ấm với `alpha = 0.40` để dẫn đường rõ nét.\n- Khi `isAligned == true` (đã khớp): chuyển sang màu xanh lá với `alpha = 0.18` (mờ đi hơn một nửa) để nhường không gian thị giác cho biểu cảm khuôn mặt người thật."
        }
    ]


def generate_full_questions_bank():
    """Tự động sinh và lưu trữ toàn bộ ngân hàng câu hỏi phân rõ 3 dạng: Thực tế, Kiến trúc và hàm cốt lõi, Bug."""
    real = get_real_world_scenario_questions()
    arch = get_architecture_and_code_questions()
    bugs = parse_bugs_from_bug_log()

    all_q = []
    all_q.extend(real)
    all_q.extend(arch)
    all_q.extend(bugs)

    print(f"\n==========================================")
    print(f"📊 ĐÃ PHÂN CHIA RÕ RÀNG 3 DẠNG CÂU HỎI:")
    print(f"  1. [{CAT_REAL}]: {len(real)} câu hỏi")
    print(f"  2. [{CAT_ARCH}]: {len(arch)} câu hỏi")
    print(f"  3. [{CAT_BUGS}]: {len(bugs)} câu hỏi")
    print(f"  => Tổng cộng: {len(all_q)} câu hỏi")
    print(f"==========================================\n")

    with open(QUESTIONS_PATH, "w", encoding="utf-8") as f:
        json.dump(all_q, f, ensure_ascii=False, indent=2)

    return all_q


if __name__ == "__main__":
    generate_full_questions_bank()
