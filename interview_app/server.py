#!/usr/bin/env python3
"""Local Web Server for NET_ver1 AI Interview Coach.
Chạy độc lập bằng Python 3 standard library, không cần pip install.
"""

import http.server
import json
import os
import re
import socketserver
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
QUESTIONS_FILE = os.path.join(BASE_DIR, "questions.json")
STATIC_DIR = os.path.join(BASE_DIR, "static")
DEFAULT_PORT = 8080

try:
    from auto_generator import generate_full_questions_bank
except ImportError:
    generate_full_questions_bank = None


def load_questions():
    if not os.path.exists(QUESTIONS_FILE) and generate_full_questions_bank:
        return generate_full_questions_bank()
    try:
        with open(QUESTIONS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not data and generate_full_questions_bank:
                return generate_full_questions_bank()
            return data
    except Exception as e:
        print(f"Lỗi load questions: {e}")
        if generate_full_questions_bank:
            return generate_full_questions_bank()
        return []


def save_questions(questions):
    try:
        with open(QUESTIONS_FILE, "w", encoding="utf-8") as f:
            json.dump(questions, f, ensure_ascii=False, indent=2)
        return True
    except Exception as e:
        print(f"Lỗi save questions: {e}")
        return False


def call_gemini_api(api_key: str, model_name: str, prompt: str):
    """Gọi trực tiếp Google Gemini REST API qua urllib chuẩn."""
    if not model_name:
        model_name = "gemini-2.5-flash"
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={api_key}"
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": prompt}]
            }
        ],
        "generationConfig": {
            "temperature": 0.3,
            "responseMimeType": "application/json"
        }
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            candidate = data.get("candidates", [{}])[0]
            text = candidate.get("content", {}).get("parts", [{}])[0].get("text", "")
            return json.loads(text)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        raise RuntimeError(f"Gemini API HTTP {e.code}: {err_body}")
    except Exception as e:
        raise RuntimeError(f"Lỗi gọi Gemini API: {str(e)}")


def offline_rubric_evaluate(question: dict, user_answer: str) -> dict:
    """Chấm điểm offline bằng bộ tiêu chí Rubric & phân tích từ khoá, độ sâu lập luận."""
    answer_text = user_answer.strip().lower()
    rubric = question.get("rubric", {})
    keywords = rubric.get("keywords", [])
    criteria = rubric.get("criteria", [])
    
    if len(answer_text) < 15:
        return {
            "score": 10,
            "summary": "Câu trả lời quá ngắn hoặc chưa đi vào trọng tâm kỹ thuật của câu hỏi.",
            "strengths": ["Đã thử đưa ra phản hồi ban đầu."],
            "missingPoints": [
                "Cần giải thích chi tiết cơ chế hoạt động bên dưới.",
                "Cần liên hệ với các hàm, class hoặc đặc tả kỹ thuật cụ thể trong source code."
            ],
            "idealAnswer": question.get("idealAnswer", ""),
            "followUpQuestion": "Bạn có thể chỉ ra class hoặc file nào trong dự án chịu trách nhiệm cho phần logic này không?"
        }

    # Đếm số từ khoá khớp
    matched_keywords = [kw for kw in keywords if kw.lower() in answer_text]
    kw_ratio = len(matched_keywords) / max(len(keywords), 1)
    
    # Đánh giá độ dài và cấu trúc
    word_count = len(user_answer.split())
    depth_bonus = min(word_count / 120.0, 1.0) * 25  # tối đa 25 điểm độ sâu
    kw_score = min(kw_ratio * 55.0, 55.0)           # tối đa 55 điểm từ khoá chuyên môn
    base_score = 20                                 # 20 điểm khởi đầu khi có phân tích
    
    total_score = min(int(base_score + kw_score + depth_bonus), 100)
    
    strengths = []
    missing = []
    
    if matched_keywords:
        strengths.append(f"Đã đề cập chính xác các khái niệm then chốt: {', '.join(matched_keywords[:4])}.")
    if word_count > 60:
        strengths.append("Lập luận có cấu trúc và có sự phân tích chi tiết các khía cạnh kỹ thuật.")
    if not strengths:
        strengths.append("Đã nắm được định hướng chung của bài toán.")
        
    unmatched_keywords = [kw for kw in keywords if kw.lower() not in answer_text]
    if unmatched_keywords:
        missing.append(f"Chưa đào sâu vào các thuật ngữ/cơ chế quan trọng: {', '.join(unmatched_keywords[:4])}.")
    
    cat = question.get("category", "Kiến trúc và hàm cốt lõi")
    if total_score >= 80:
        summary = f"Rất tốt! Bạn nắm rất vững bản chất của câu hỏi thuộc nhóm [{cat}] trong dự án NET_ver1."
    elif total_score >= 50:
        summary = f"Khá tốt. Bạn hiểu được hướng đi chung của bài toán [{cat}], tuy nhiên cần bổ sung thêm dẫn chứng mã nguồn cụ thể và phân tích sâu cơ chế bên dưới."
    else:
        summary = f"Cần cải thiện. Câu trả lời cho dạng câu hỏi [{cat}] còn chung chung, chưa chạm được vào nguyên lý hoặc nguyên nhân kỹ thuật gốc rễ trong dự án."

    if cat == "Thực tế":
        followup = "Nếu người dùng gặp tình huống này trên thiết bị đời cũ hoặc trong môi trường thiếu sáng cực đoan, bạn sẽ tinh chỉnh ngưỡng hoặc UX như thế nào?"
        default_missing = "Nên phân tích rõ hơn sự đánh đổi (trade-off) giữa trải nghiệm người dùng (UX) và giới hạn kỹ thuật."
    elif cat == "Bug":
        followup = "Làm thế nào để thiết kế thêm một bài kiểm tra tự động (Unit Test / Regression Test) đảm bảo lỗi này không bao giờ lọt qua CI/CD?"
        default_missing = "Nên bổ sung tên hàm test cụ thể trong NET_ver1Tests chặn lỗi này tái diễn."
    else:
        followup = "Tại sao thiết kế hàm cốt lõi này lại giúp tách biệt tầng Domain khỏi AVFoundation/RealityKit và tối ưu việc kiểm thử?"
        default_missing = "Nên liên hệ sâu hơn tới cấu trúc dữ liệu, độ phức tạp thuật toán và tính thread-safe của hàm."

    return {
        "score": total_score,
        "summary": summary,
        "strengths": strengths,
        "missingPoints": missing if missing else [default_missing],
        "idealAnswer": question.get("idealAnswer", ""),
        "followUpQuestion": followup
    }


class InterviewRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC_DIR, **kwargs)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        path = url.path

        if path == "/api/questions":
            self.send_json_response(load_questions())
        elif path == "/api/categories":
            questions = load_questions()
            cats = {}
            for q in questions:
                c = q.get("category", "Chung")
                cats[c] = cats.get(c, 0) + 1
            self.send_json_response({"categories": cats, "total": len(questions)})
        elif path == "/api/source-files":
            files = self.get_available_source_files()
            self.send_json_response({"files": files})
        elif path == "/api/status":
            self.send_json_response({"status": "ok", "app": "NET_ver1 AI Interview Coach"})
        else:
            # Phục vụ static files
            super().do_GET()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        path = url.path
        
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length)
        
        try:
            body = json.loads(post_data.decode("utf-8")) if post_data else {}
        except Exception:
            body = {}

        if path == "/api/evaluate":
            self.handle_evaluate(body)
        elif path == "/api/sync-questions":
            if generate_full_questions_bank:
                all_q = generate_full_questions_bank()
                self.send_json_response({"success": True, "total": len(all_q), "questions": all_q})
            else:
                self.send_json_response({"success": True, "questions": load_questions()})
        elif path == "/api/generate-question":
            self.handle_generate_question(body)
        elif path == "/api/scan-file":
            self.handle_scan_file(body)
        else:
            self.send_error(404, "Not Found")

    def handle_evaluate(self, body):
        question_id = body.get("questionId")
        user_answer = body.get("userAnswer", "")
        api_key = body.get("apiKey") or os.environ.get("GEMINI_API_KEY", "")
        model_name = body.get("model", "gemini-2.5-flash")

        questions = load_questions()
        target_q = next((q for q in questions if q["id"] == question_id), None)

        if not target_q:
            self.send_json_response({"error": f"Không tìm thấy câu hỏi với ID {question_id}"}, status=404)
            return

        # Nếu có API Key, dùng Google Gemini API để chấm điểm thông minh
        if api_key:
            prompt = f"""Bạn là một Chuyên gia Phỏng vấn Cấp cao (Senior Staff iOS & RealityKit Engineer) tại một công ty công nghệ hàng đầu, đang phỏng vấn ứng viên về dự án camera chân dung 3D 'NET_ver1'.

Dưới đây là thông tin câu hỏi (thuộc dạng: {target_q.get('category', 'Kiến trúc và hàm cốt lõi')}) và câu trả lời của ứng viên:
---
DẠNG CÂU HỎI: {target_q.get('category')} ({target_q.get('subCategory', '')})
CÂU HỎI: {target_q.get('title')}
MÔ TẢ CÂU HỎI: {target_q.get('question')}
CODE LIÊN QUAN:
{target_q.get('codeSnippet', '')}
ĐÁP ÁN CHUẨN CỦA DỰ ÁN:
{target_q.get('idealAnswer', '')}
TIÊU CHÍ CHẤM ĐIỂM (RUBRIC):
- Từ khoá bắt buộc: {json.dumps(target_q.get('rubric', {}).get('keywords', []), ensure_ascii=False)}
- Tiêu chí: {json.dumps(target_q.get('rubric', {}).get('criteria', []), ensure_ascii=False)}
---
CÂU TRẢ LỜI CỦA ỨNG VIÊN:
{user_answer}
---

Hãy chấm điểm và phản hồi bằng tiếng Việt theo định dạng JSON với cấu trúc CHÍNH XÁC sau:
{{
  "score": <số nguyên từ 0 đến 100>,
  "summary": "<Nhận xét tổng quan sắc bén, mang tính xây dựng cao>",
  "strengths": ["<Điểm ứng viên đã trả lời đúng/tốt>", "..."],
  "missingPoints": ["<Ý còn thiếu hoặc sai lệch kỹ thuật cần bổ sung>", "..."],
  "idealAnswer": "<Đáp án mẫu cô đọng và chuẩn xác>",
  "followUpQuestion": "<Một câu hỏi đào sâu mở rộng tiếp theo để thử thách thêm ứng viên>"
}}
Chỉ trả về duy nhất chuỗi JSON hợp lệ, không bọc markdown thừa.
"""
            try:
                result = call_gemini_api(api_key, model_name, prompt)
                self.send_json_response(result)
                return
            except Exception as e:
                print(f"Gemini API thất bại, chuyển sang chấm offline: {e}")
                # Fallback sang chấm offline nếu API lỗi
                res = offline_rubric_evaluate(target_q, user_answer)
                res["warning"] = f"Không gọi được Gemini API ({str(e)}), hệ thống đã chấm bằng Bộ quy chuẩn Offline (Rubric Engine)."
                self.send_json_response(res)
                return
        else:
            # Chế độ chấm offline bằng Rubric
            res = offline_rubric_evaluate(target_q, user_answer)
            self.send_json_response(res)

    def handle_scan_file(self, body):
        file_path = body.get("filePath", "")
        full_path = os.path.join(PROJECT_ROOT, file_path)
        if not os.path.exists(full_path) or not os.path.isfile(full_path):
            self.send_json_response({"error": "File không tồn tại"}, status=400)
            return

        try:
            with open(full_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
            preview = "".join(lines[:120])
            self.send_json_response({
                "filePath": file_path,
                "totalLines": len(lines),
                "preview": preview
            })
        except Exception as e:
            self.send_json_response({"error": str(e)}, status=500)

    def handle_generate_question(self, body):
        file_path = body.get("filePath", "")
        category = body.get("category", "Kiến trúc và hàm cốt lõi")
        difficulty = body.get("difficulty", "Senior")
        api_key = body.get("apiKey") or os.environ.get("GEMINI_API_KEY", "")
        model_name = body.get("model", "gemini-2.5-flash")

        full_path = os.path.join(PROJECT_ROOT, file_path) if file_path else ""
        file_content = ""
        if full_path and os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8") as f:
                file_content = "".join(f.readlines()[:150])

        if not api_key:
            self.send_json_response({
                "error": "Vui lòng cấu hình Gemini API Key trong phần Cài đặt (Settings) để sinh câu hỏi mới tự động từ AI!"
            }, status=400)
            return

        prompt = f"""Dựa vào đoạn mã nguồn sau đây của dự án iOS/RealityKit 'NET_ver1':
File: {file_path}
Nội dung mã nguồn:
{file_content}

Hãy tạo 01 câu hỏi phỏng vấn kỹ thuật chất lượng cao theo chủ đề '{category}' với độ khó '{difficulty}'.
Câu hỏi cần đào sâu vào nguyên lý thiết kế, lỗi tiềm ẩn, bài học kinh nghiệm hoặc giải thích các đoạn mã then chốt trong file này.

Trả về kết quả bằng tiếng Việt theo định dạng JSON CHÍNH XÁC:
{{
  "id": "Q-GEN-{os.urandom(3).hex().upper()}",
  "title": "<Tiêu đề ngắn gọn của câu hỏi>",
  "category": "{category}",
  "difficulty": "{difficulty}",
  "relatedFiles": ["{file_path}"],
  "codeSnippet": "<Đoạn code ngắn tiêu biểu từ file được trích dẫn>",
  "question": "<Nội dung câu hỏi chi tiết, có thể chia ý 1, 2>",
  "hints": ["<Gợi ý 1>", "<Gợi ý 2>"],
  "rubric": {{
    "keywords": ["<từ khoá 1>", "<từ khoá 2>", "<từ khoá 3>", "<từ khoá 4>"],
    "criteria": ["<tiêu chí 1>", "<tiêu chí 2>"]
  }},
  "idealAnswer": "<Đáp án chuẩn chi tiết và chuyên sâu>"
}}
Chỉ trả về JSON thuần tuý.
"""
        try:
            new_q = call_gemini_api(api_key, model_name, prompt)
            questions = load_questions()
            questions.append(new_q)
            save_questions(questions)
            self.send_json_response({"success": True, "question": new_q})
        except Exception as e:
            self.send_json_response({"error": f"Lỗi sinh câu hỏi: {str(e)}"}, status=500)

    def get_available_source_files(self):
        targets = []
        for root, _, files in os.walk(os.path.join(PROJECT_ROOT, "NET_ver1")):
            for f in files:
                if f.endswith(".swift"):
                    targets.append(os.path.relpath(os.path.join(root, f), PROJECT_ROOT))
        for root, _, files in os.walk(os.path.join(PROJECT_ROOT, "tools")):
            for f in files:
                if f.endswith(".py"):
                    targets.append(os.path.relpath(os.path.join(root, f), PROJECT_ROOT))
        for root, _, files in os.walk(os.path.join(PROJECT_ROOT, "docs")):
            for f in files:
                if f.endswith(".md"):
                    targets.append(os.path.relpath(os.path.join(root, f), PROJECT_ROOT))
        return sorted(targets)

    def send_json_response(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


def run_server():
    port = DEFAULT_PORT
    for p in range(DEFAULT_PORT, DEFAULT_PORT + 20):
        try:
            with socketserver.TCPServer(("", p), InterviewRequestHandler) as httpd:
                print(f"\n========================================================")
                print(f"🚀 NET_ver1 AI Interview Coach đang chạy tại:")
                print(f"👉 http://localhost:{p}")
                print(f"👉 http://127.0.0.1:{p}")
                print(f"========================================================\n")
                print("Nhấn Ctrl + C để dừng máy chủ.")
                httpd.serve_forever()
                break
        except OSError as e:
            if "Address already in use" in str(e):
                continue
            raise


if __name__ == "__main__":
    run_server()
