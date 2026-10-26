/**
 * NET_ver1 AI Interview Coach - Core Client Logic
 * Tự động đồng bộ toàn bộ câu hỏi từ source code và docs/BUG-LOG.md.
 * Người dùng chỉ việc chọn câu hỏi và làm bài, có AI chấm điểm tức thì.
 */

// State
let allQuestions = [];
let activeQuestionId = null;
let currentCategory = 'ALL';
let currentDifficulty = 'ALL';
let currentSearch = '';
let onlyUnanswered = false;

// LocalStorage Keys
const STORAGE_CONFIG = 'net_ver1_interview_config';
const STORAGE_SUBMISSIONS = 'net_ver1_interview_submissions';

// Default Config
let appConfig = {
  provider: 'offline', // 'gemini' | 'offline'
  geminiKey: '',
  geminiModel: 'gemini-2.5-flash'
};

// Submissions Map: { [qId]: { answer: string, result: object, timestamp: number } }
let submissions = {};

// DOM Elements
const el = {
  // Stats
  statTotal: document.getElementById('stat-total-count'),
  statCompleted: document.getElementById('stat-completed-count'),
  statAvgScore: document.getElementById('stat-avg-score'),
  btnRandomHeader: document.getElementById('btn-random-header'),
  
  // Filters
  inputSearch: document.getElementById('input-search'),
  categoryTabs: document.getElementById('category-tabs'),
  selectDifficulty: document.getElementById('select-difficulty'),
  checkUnanswered: document.getElementById('check-unanswered'),
  visibleCountBadge: document.getElementById('visible-count-badge'),
  questionsList: document.getElementById('questions-list'),

  // Arena
  emptyState: document.getElementById('empty-state'),
  arenaContent: document.getElementById('arena-content'),
  btnPickRandom: document.getElementById('btn-pick-random'),
  arenaQid: document.getElementById('arena-qid'),
  arenaCategory: document.getElementById('arena-category'),
  arenaDifficulty: document.getElementById('arena-difficulty'),
  arenaFilesWrap: document.getElementById('arena-files-wrap'),
  arenaTitle: document.getElementById('arena-title'),
  arenaDescription: document.getElementById('arena-description'),
  arenaCodeContainer: document.getElementById('arena-code-container'),
  arenaCodeSnippet: document.getElementById('arena-code-snippet'),
  btnCopyCode: document.getElementById('btn-copy-code'),
  btnToggleHints: document.getElementById('btn-toggle-hints'),
  hintsBody: document.getElementById('hints-body'),
  hintsList: document.getElementById('hints-list'),

  // Editor
  charCounter: document.getElementById('char-counter'),
  answerTextarea: document.getElementById('user-answer-textarea'),
  btnResetAnswer: document.getElementById('btn-reset-answer'),
  btnPeekIdeal: document.getElementById('btn-peek-ideal'),
  btnSubmitAnswer: document.getElementById('btn-submit-answer'),
  submitSpinner: document.getElementById('submit-spinner'),
  submitBtnText: document.getElementById('submit-btn-text'),

  // Results
  resultCard: document.getElementById('result-card'),
  resultScoreVal: document.getElementById('result-score-val'),
  resultGradeBadge: document.getElementById('result-grade-badge'),
  resultEvalMode: document.getElementById('result-eval-mode'),
  resultSummaryText: document.getElementById('result-summary-text'),
  resultStrengthsList: document.getElementById('result-strengths-list'),
  resultMissingList: document.getElementById('result-missing-list'),
  resultIdealBox: document.getElementById('result-ideal-box'),
  resultIdealContent: document.getElementById('result-ideal-content'),
  resultFollowupBox: document.getElementById('result-followup-box'),
  resultFollowupText: document.getElementById('result-followup-text'),

  // Settings Modal
  btnSettingsModal: document.getElementById('btn-settings-modal'),
  settingsModalBackdrop: document.getElementById('settings-modal-backdrop'),
  btnCloseSettings: document.getElementById('btn-close-settings'),
  btnCancelSettings: document.getElementById('btn-cancel-settings'),
  btnSaveSettings: document.getElementById('btn-save-settings'),
  settingProvider: document.getElementById('setting-provider'),
  groupGeminiKey: document.getElementById('group-gemini-key'),
  settingGeminiKey: document.getElementById('setting-gemini-key'),
  btnToggleKeyVis: document.getElementById('btn-toggle-key-vis'),
  groupGeminiModel: document.getElementById('group-gemini-model'),
  settingGeminiModel: document.getElementById('setting-gemini-model'),
  apiStatusText: document.getElementById('api-status-text'),

  toastContainer: document.getElementById('toast-container')
};

// ==========================================================================
// Initialization
// ==========================================================================
async function init() {
  loadStoredData();
  setupEventListeners();
  await fetchQuestions();
  updateStats();
  applySettingsToUI();
}

function loadStoredData() {
  try {
    const rawConfig = localStorage.getItem(STORAGE_CONFIG);
    if (rawConfig) appConfig = Object.assign(appConfig, JSON.parse(rawConfig));

    const rawSubs = localStorage.getItem(STORAGE_SUBMISSIONS);
    if (rawSubs) submissions = JSON.parse(rawSubs);
  } catch (err) {
    console.error('Lỗi nạp LocalStorage:', err);
  }
}

function saveStoredData() {
  try {
    localStorage.setItem(STORAGE_CONFIG, JSON.stringify(appConfig));
    localStorage.setItem(STORAGE_SUBMISSIONS, JSON.stringify(submissions));
  } catch (err) {
    console.error('Lỗi lưu LocalStorage:', err);
  }
}

// ==========================================================================
// Data Fetching & Questions Rendering
// ==========================================================================
async function fetchQuestions() {
  try {
    const res = await fetch('/api/questions');
    if (!res.ok) throw new Error('Không thể tải danh sách câu hỏi');
    allQuestions = await res.json();
    updateCategoryTabCounts();
    renderQuestionsList();
    updateStats();

    // Tự động mở câu đầu tiên nếu chưa chọn
    if (allQuestions.length > 0 && !activeQuestionId) {
      selectQuestion(allQuestions[0].id);
    }
  } catch (err) {
    showToast(`Lỗi: ${err.message}`, 'error');
  }
}

// 3 Dạng câu hỏi chuẩn
const QUESTION_TYPES = [
  {
    key: 'Thực tế',
    icon: '📱',
    headerLabel: 'Dạng 1 • Thực tế',
    groupClass: 'q-group-real',
    itemClass: 'item-real',
    badgeClass: 'cat-real',
    hint: 'Phân tích rõ: 1. Bản chất tình huống thực tế & UX | 2. Giải pháp xử lý trong code | 3. Đánh đổi (Trade-offs) & Edge cases',
    template: '1. **Bản chất bài toán thực tế & UX**:\n- \n\n2. **Cơ chế xử lý trong mã nguồn**:\n- \n\n3. **Đánh đổi kỹ thuật (Trade-offs) & Trường hợp biên**:\n- '
  },
  {
    key: 'Kiến trúc và hàm cốt lõi',
    icon: '🏛️',
    headerLabel: 'Dạng 2 • Kiến trúc và hàm cốt lõi',
    groupClass: 'q-group-arch',
    itemClass: 'item-arch',
    badgeClass: 'cat-arch',
    hint: 'Phân tích rõ: 1. Vai trò kiến trúc & Thiết kế hàm | 2. Cơ chế hoạt động chi tiết | 3. Lợi ích hiệu năng, bảo trì & Unit Test',
    template: '1. **Vai trò kiến trúc & Thiết kế hàm cốt lõi**:\n- \n\n2. **Cơ chế hoạt động chi tiết bên dưới**:\n- \n\n3. **Lợi ích về Hiệu năng, Bảo trì & Unit Test**:\n- '
  },
  {
    key: 'Bug',
    icon: '🐛',
    headerLabel: 'Dạng 3 • Bug',
    groupClass: 'q-group-bug',
    itemClass: 'item-bug',
    badgeClass: 'cat-bug',
    hint: 'Phân tích rõ: 1. Nguyên nhân gốc rễ (Root Cause) | 2. Giải pháp khắc phục trong code | 3. Unit Test chặn lỗi tái diễn',
    template: '1. **Nguyên nhân gốc rễ**:\n- \n\n2. **Giải pháp khắc phục**:\n- \n\n3. **Biện pháp phòng ngừa & Unit Test**:\n- '
  }
];

function getTypeMeta(category) {
  return QUESTION_TYPES.find(t => t.key === category) || QUESTION_TYPES[1];
}

function setCategoryFilter(category) {
  currentCategory = category;

  // Đồng bộ trạng thái active trên các tab pill
  document.querySelectorAll('.cat-pill').forEach(p => {
    p.classList.toggle('active', p.dataset.category === currentCategory);
  });

  // Đồng bộ trạng thái active trên 3 thẻ tổng quan đầu trang
  document.querySelectorAll('.type-card').forEach(card => {
    card.classList.toggle('active', card.dataset.category === currentCategory);
  });

  renderQuestionsList();
}

function updateCategoryTabCounts() {
  const catAllBtn = document.getElementById('cat-all');
  const catRealBtn = document.getElementById('cat-real');
  const catCodeBtn = document.getElementById('cat-code');
  const catBugBtn = document.getElementById('cat-bug');

  const realQuestions = allQuestions.filter(q => q.category === 'Thực tế');
  const archQuestions = allQuestions.filter(q => q.category === 'Kiến trúc và hàm cốt lõi');
  const bugQuestions = allQuestions.filter(q => q.category === 'Bug');

  const countCompleted = (list) => list.filter(q => typeof submissions[q.id]?.result?.score === 'number').length;

  if (catAllBtn) catAllBtn.innerHTML = `Tất cả <span style="opacity:0.75; font-size:0.75rem;">(${allQuestions.length})</span>`;
  if (catRealBtn) catRealBtn.innerHTML = `<span class="cat-icon">📱</span> Thực tế <span style="opacity:0.75; font-size:0.75rem;">(${realQuestions.length})</span>`;
  if (catCodeBtn) catCodeBtn.innerHTML = `<span class="cat-icon">🏛️</span> Kiến trúc và hàm cốt lõi <span style="opacity:0.75; font-size:0.75rem;">(${archQuestions.length})</span>`;
  if (catBugBtn) catBugBtn.innerHTML = `<span class="cat-icon">🐛</span> Bug <span style="opacity:0.75; font-size:0.75rem;">(${bugQuestions.length})</span>`;

  // Cập nhật số lượng trên 3 thẻ tổng quan (3 Dạng câu hỏi)
  const elCountReal = document.getElementById('type-count-real');
  const elCountArch = document.getElementById('type-count-arch');
  const elCountBug = document.getElementById('type-count-bug');

  if (elCountReal) elCountReal.textContent = `${countCompleted(realQuestions)}/${realQuestions.length} đã làm`;
  if (elCountArch) elCountArch.textContent = `${countCompleted(archQuestions)}/${archQuestions.length} đã làm`;
  if (elCountBug) elCountBug.textContent = `${countCompleted(bugQuestions)}/${bugQuestions.length} đã làm`;
}

function renderQuestionsList() {
  const filtered = allQuestions.filter(q => {
    // Lọc chưa làm
    if (onlyUnanswered) {
      const sub = submissions[q.id];
      if (sub && typeof sub.result?.score === 'number') return false;
    }
    // Lọc chuyên mục (3 dạng)
    if (currentCategory !== 'ALL' && q.category !== currentCategory) return false;
    // Lọc độ khó
    if (currentDifficulty !== 'ALL' && q.difficulty !== currentDifficulty) return false;
    // Lọc tìm kiếm
    if (currentSearch) {
      const s = currentSearch.toLowerCase();
      const matchTitle = q.title.toLowerCase().includes(s);
      const matchId = q.id.toLowerCase().includes(s);
      const matchDesc = q.question.toLowerCase().includes(s);
      const matchCat = (q.category || '').toLowerCase().includes(s) || (q.subCategory || '').toLowerCase().includes(s);
      const matchFiles = (q.relatedFiles || []).some(f => f.toLowerCase().includes(s));
      if (!matchTitle && !matchId && !matchDesc && !matchCat && !matchFiles) return false;
    }
    return true;
  });

  el.visibleCountBadge.textContent = `${filtered.length} câu`;
  el.questionsList.innerHTML = '';

  if (filtered.length === 0) {
    el.questionsList.innerHTML = `
      <div style="text-align:center; padding: 2rem 1rem; color: var(--text-dim); font-size: 0.85rem;">
        Không tìm thấy câu hỏi phù hợp với bộ lọc hiện tại.
      </div>
    `;
    return;
  }

  // Nhóm rõ ràng theo 3 dạng câu hỏi: Thực tế -> Kiến trúc và hàm cốt lõi -> Bug
  QUESTION_TYPES.forEach(typeInfo => {
    const groupQuestions = filtered.filter(q => q.category === typeInfo.key);
    if (groupQuestions.length === 0) return;

    const header = document.createElement('div');
    header.className = `q-group-header ${typeInfo.groupClass}`;
    header.innerHTML = `
      <span>${typeInfo.icon} ${typeInfo.headerLabel}</span>
      <span class="q-group-badge">${groupQuestions.length} câu</span>
    `;
    el.questionsList.appendChild(header);

    groupQuestions.forEach(q => {
      const sub = submissions[q.id];
      const isCompleted = sub && typeof sub.result?.score === 'number';
      const isActive = q.id === activeQuestionId;

      const item = document.createElement('div');
      item.className = `q-card-item ${typeInfo.itemClass} ${isActive ? 'active' : ''}`;
      item.id = `q-item-${q.id}`;

      let statusHtml = '<span class="q-card-status">Chưa làm</span>';
      if (isCompleted) {
        statusHtml = `<span class="q-card-status passed">${sub.result.score}/100</span>`;
      }

      item.innerHTML = `
        <div class="q-card-top">
          <span class="q-card-id">${q.id}</span>
          ${statusHtml}
        </div>
        <h4 class="q-card-title">${q.title}</h4>
        <div class="q-card-meta">
          <span class="badge badge-category ${typeInfo.badgeClass}" style="font-size:0.65rem;">${typeInfo.icon} ${q.category}</span>
          <span class="badge badge-difficulty">${q.difficulty}</span>
          ${q.subCategory ? `<span class="badge badge-neutral" style="font-size:0.62rem; text-transform:none;">${q.subCategory}</span>` : ''}
        </div>
      `;

      item.addEventListener('click', () => selectQuestion(q.id));
      el.questionsList.appendChild(item);
    });
  });
}

function selectQuestion(qId) {
  activeQuestionId = qId;
  const q = allQuestions.find(item => item.id === qId);
  if (!q) return;

  const typeInfo = getTypeMeta(q.category);

  // Cập nhật active class ở danh sách
  document.querySelectorAll('.q-card-item').forEach(card => card.classList.remove('active'));
  const currentCard = document.getElementById(`q-item-${qId}`);
  if (currentCard) currentCard.classList.add('active');

  // Hiển thị Arena
  el.emptyState.classList.add('hidden');
  el.arenaContent.classList.remove('hidden');

  // Gán thông tin câu hỏi và dạng câu hỏi
  el.arenaQid.textContent = q.id;
  el.arenaCategory.textContent = `${typeInfo.icon} ${q.category}`;
  el.arenaCategory.className = `badge badge-category ${typeInfo.badgeClass}`;

  const elSubCat = document.getElementById('arena-subcategory');
  if (elSubCat) {
    if (q.subCategory) {
      elSubCat.textContent = q.subCategory;
      elSubCat.classList.remove('hidden');
    } else {
      elSubCat.classList.add('hidden');
    }
  }

  el.arenaDifficulty.textContent = q.difficulty;
  el.arenaTitle.textContent = q.title;
  el.arenaDescription.textContent = q.question;

  // Cập nhật gợi ý cấu trúc câu trả lời & khung mẫu theo đúng dạng câu hỏi (Thực tế / Kiến trúc và hàm cốt lõi / Bug)
  const elAnswerHint = document.getElementById('arena-answer-hint');
  if (elAnswerHint) elAnswerHint.textContent = typeInfo.hint;
  const elTemplateBtn = document.getElementById('btn-template-snippet');
  if (elTemplateBtn) {
    elTemplateBtn.dataset.snippet = typeInfo.template;
    elTemplateBtn.innerHTML = `📝 Khung chuẩn (${q.category})`;
  }

  // Related files
  el.arenaFilesWrap.innerHTML = '';
  if (q.relatedFiles && q.relatedFiles.length > 0) {
    q.relatedFiles.forEach(f => {
      const chip = document.createElement('span');
      chip.className = 'file-chip';
      chip.textContent = f.split('/').pop();
      chip.title = f;
      el.arenaFilesWrap.appendChild(chip);
    });
  }

  // Code Snippet
  if (q.codeSnippet && q.codeSnippet.trim()) {
    el.arenaCodeContainer.classList.remove('hidden');
    el.arenaCodeSnippet.textContent = q.codeSnippet;
  } else {
    el.arenaCodeContainer.classList.add('hidden');
  }

  // Hints
  el.hintsBody.classList.add('hidden');
  el.btnToggleHints.classList.remove('open');
  el.hintsList.innerHTML = '';
  if (q.hints && q.hints.length > 0) {
    q.hints.forEach(h => {
      const li = document.createElement('li');
      li.textContent = h;
      el.hintsList.appendChild(li);
    });
    el.btnToggleHints.parentElement.classList.remove('hidden');
  } else {
    el.btnToggleHints.parentElement.classList.add('hidden');
  }

  // Khôi phục câu trả lời cũ hoặc bản nháp
  const previousSub = submissions[q.id];
  if (previousSub) {
    el.answerTextarea.value = previousSub.answer || '';
    if (previousSub.result) {
      renderEvaluationResult(previousSub.result, false);
    } else {
      el.resultCard.classList.add('hidden');
    }
  } else {
    el.answerTextarea.value = '';
    el.resultCard.classList.add('hidden');
  }

  updateWordCount();
  el.answerTextarea.focus();
}

function pickRandomQuestion() {
  if (allQuestions.length === 0) return;
  // Ưu tiên câu chưa làm nếu có
  const uncompleted = allQuestions.filter(q => !submissions[q.id]?.result);
  const pool = uncompleted.length > 0 ? uncompleted : allQuestions;
  const randomIndex = Math.floor(Math.random() * pool.length);
  selectQuestion(pool[randomIndex].id);
  showToast(`Đã chọn ngẫu nhiên: ${pool[randomIndex].id}`, 'info');
}

function updateWordCount() {
  const text = el.answerTextarea.value.trim();
  const words = text ? text.split(/\s+/).length : 0;
  const chars = text.length;
  el.charCounter.textContent = `${words} từ • ${chars} ký tự`;
}

// ==========================================================================
// AI Evaluation Handler
// ==========================================================================
async function submitAnswer() {
  const q = allQuestions.find(item => item.id === activeQuestionId);
  if (!q) return;

  const answer = el.answerTextarea.value.trim();
  if (!answer) {
    showToast('Vui lòng nhập câu trả lời trước khi nộp!', 'warning');
    el.answerTextarea.focus();
    return;
  }

  // UI Loading State
  el.btnSubmitAnswer.disabled = true;
  el.submitSpinner.classList.remove('hidden');

  try {
    const payload = {
      questionId: q.id,
      userAnswer: answer,
      apiKey: appConfig.provider === 'gemini' ? appConfig.geminiKey : '',
      model: appConfig.geminiModel
    };

    const res = await fetch('/api/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.error || 'Lỗi từ máy chủ khi chấm điểm');
    }

    const evalResult = await res.json();

    // Lưu kết quả vào submissions
    submissions[q.id] = {
      answer: answer,
      result: evalResult,
      timestamp: Date.now()
    };
    saveStoredData();

    // Hiển thị kết quả đánh giá
    renderEvaluationResult(evalResult, true);
    updateStats();
    renderQuestionsList();

    if (evalResult.warning) {
      showToast(evalResult.warning, 'warning');
    } else {
      showToast(`Đã chấm điểm: ${evalResult.score}/100!`, 'success');
    }

    // Scroll nhẹ xuống kết quả
    el.resultCard.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  } catch (err) {
    showToast(`Chấm điểm thất bại: ${err.message}`, 'error');
  } finally {
    el.btnSubmitAnswer.disabled = false;
    el.submitSpinner.classList.add('hidden');
  }
}

function renderEvaluationResult(evalResult, animate = false) {
  el.resultCard.classList.remove('hidden');

  const score = evalResult.score || 0;
  
  // Hiệu ứng số điểm nhảy
  if (animate) {
    let current = 0;
    const duration = 700;
    const stepTime = Math.max(10, Math.floor(duration / Math.max(score, 1)));
    const timer = setInterval(() => {
      current += 1;
      el.resultScoreVal.textContent = current;
      if (current >= score) {
        clearInterval(timer);
        el.resultScoreVal.textContent = score;
      }
    }, stepTime);
  } else {
    el.resultScoreVal.textContent = score;
  }

  // Đổi màu điểm số theo mức
  const dial = document.getElementById('score-dial');
  if (score >= 80) {
    dial.style.borderColor = 'var(--accent-emerald)';
    dial.style.boxShadow = '0 0 20px var(--accent-emerald-glow)';
    el.resultScoreVal.style.color = 'var(--accent-emerald)';
    el.resultGradeBadge.textContent = 'Xuất sắc';
    el.resultGradeBadge.style.color = 'var(--accent-emerald)';
    el.resultGradeBadge.style.borderColor = 'rgba(16, 185, 129, 0.4)';
    el.resultGradeBadge.style.background = 'rgba(16, 185, 129, 0.15)';
  } else if (score >= 60) {
    dial.style.borderColor = 'var(--accent-cyan)';
    dial.style.boxShadow = '0 0 20px var(--accent-cyan-glow)';
    el.resultScoreVal.style.color = 'var(--accent-cyan)';
    el.resultGradeBadge.textContent = 'Khá tốt';
    el.resultGradeBadge.style.color = 'var(--accent-cyan)';
    el.resultGradeBadge.style.borderColor = 'rgba(56, 189, 248, 0.4)';
    el.resultGradeBadge.style.background = 'rgba(56, 189, 248, 0.15)';
  } else {
    dial.style.borderColor = 'var(--accent-coral)';
    dial.style.boxShadow = '0 0 20px var(--accent-coral-glow)';
    el.resultScoreVal.style.color = 'var(--accent-coral)';
    el.resultGradeBadge.textContent = 'Cần cải thiện';
    el.resultGradeBadge.style.color = 'var(--accent-coral)';
    el.resultGradeBadge.style.borderColor = 'rgba(244, 63, 94, 0.4)';
    el.resultGradeBadge.style.background = 'rgba(244, 63, 94, 0.15)';
  }

  // Động cơ chấm
  el.resultEvalMode.textContent = appConfig.provider === 'gemini' && appConfig.geminiKey
    ? `Gemini AI (${appConfig.geminiModel})`
    : 'Bộ tiêu chuẩn Offline (Rubric Engine)';

  // Nhận xét tổng quan
  el.resultSummaryText.textContent = evalResult.summary || 'Đã hoàn tất đánh giá.';

  // Strengths List
  el.resultStrengthsList.innerHTML = '';
  if (evalResult.strengths && evalResult.strengths.length > 0) {
    evalResult.strengths.forEach(s => {
      const li = document.createElement('li');
      li.textContent = s;
      el.resultStrengthsList.appendChild(li);
    });
  } else {
    el.resultStrengthsList.innerHTML = '<li>Chưa có điểm nổi bật cụ thể.</li>';
  }

  // Missing List
  el.resultMissingList.innerHTML = '';
  if (evalResult.missingPoints && evalResult.missingPoints.length > 0) {
    evalResult.missingPoints.forEach(m => {
      const li = document.createElement('li');
      li.textContent = m;
      el.resultMissingList.appendChild(li);
    });
  } else {
    el.resultMissingList.innerHTML = '<li>Không có thiếu sót nghiêm trọng.</li>';
  }

  // Ideal Answer
  el.resultIdealContent.textContent = evalResult.idealAnswer || 'Không có đáp án mẫu.';

  // Follow-up question
  if (evalResult.followUpQuestion) {
    el.resultFollowupBox.classList.remove('hidden');
    el.resultFollowupText.textContent = evalResult.followUpQuestion;
  } else {
    el.resultFollowupBox.classList.add('hidden');
  }
}

// ==========================================================================
// Stats Calculation
// ==========================================================================
function updateStats() {
  const total = allQuestions.length;
  const completedIds = Object.keys(submissions).filter(qId => {
    return submissions[qId]?.result && typeof submissions[qId].result.score === 'number';
  });
  const completedCount = completedIds.length;

  el.statTotal.textContent = total;
  el.statCompleted.textContent = completedCount;

  if (completedCount > 0) {
    const sumScore = completedIds.reduce((sum, id) => sum + (submissions[id].result.score || 0), 0);
    const avg = Math.round(sumScore / completedCount);
    el.statAvgScore.textContent = `${avg}/100`;
  } else {
    el.statAvgScore.textContent = '--';
  }

  updateCategoryTabCounts();
}

// ==========================================================================
// Modals & Settings Management
// ==========================================================================
function applySettingsToUI() {
  el.settingProvider.value = appConfig.provider;
  el.settingGeminiKey.value = appConfig.geminiKey;
  el.settingGeminiModel.value = appConfig.geminiModel;

  const isGemini = appConfig.provider === 'gemini';
  el.groupGeminiKey.style.display = isGemini ? 'flex' : 'none';
  el.groupGeminiModel.style.display = isGemini ? 'flex' : 'none';

  if (isGemini && appConfig.geminiKey) {
    el.apiStatusText.textContent = `🟢 Chế độ AI trực tuyến: Gemini (${appConfig.geminiModel}) sẵn sàng`;
  } else {
    el.apiStatusText.textContent = '⚡ Chế độ: Bộ chuẩn Offline (Rubric Engine) - Không cần API Key';
  }
}

function openSettingsModal() {
  applySettingsToUI();
  el.settingsModalBackdrop.classList.remove('hidden');
}

function closeSettingsModal() {
  el.settingsModalBackdrop.classList.add('hidden');
}

function saveSettings() {
  appConfig.provider = el.settingProvider.value;
  appConfig.geminiKey = el.settingGeminiKey.value.trim();
  appConfig.geminiModel = el.settingGeminiModel.value;
  saveStoredData();
  applySettingsToUI();
  closeSettingsModal();
  showToast('Đã lưu cấu hình AI thành công!', 'success');
}

// ==========================================================================
// Toast Notifications
// ==========================================================================
function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = 'toast';
  
  if (type === 'error') toast.style.borderLeft = '4px solid var(--accent-coral)';
  else if (type === 'success') toast.style.borderLeft = '4px solid var(--accent-emerald)';
  else if (type === 'warning') toast.style.borderLeft = '4px solid var(--accent-amber)';
  else toast.style.borderLeft = '4px solid var(--accent-cyan)';

  toast.textContent = message;
  el.toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

// ==========================================================================
// Event Listeners Binding
// ==========================================================================
function setupEventListeners() {
  // Search with debounce
  let searchTimeout;
  el.inputSearch.addEventListener('input', (e) => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      currentSearch = e.target.value.trim();
      renderQuestionsList();
    }, 200);
  });

  // Category Tabs
  el.categoryTabs.addEventListener('click', (e) => {
    const pill = e.target.closest('.cat-pill');
    if (!pill) return;
    setCategoryFilter(pill.dataset.category);
  });

  // 3 Question Types Overview Strip Cards
  const typeStrip = document.getElementById('type-overview-strip');
  if (typeStrip) {
    typeStrip.addEventListener('click', (e) => {
      const card = e.target.closest('.type-card');
      if (!card) return;
      const targetCat = card.dataset.category;
      // Nhấn lại thẻ đang chọn thì mở lại Tất cả
      setCategoryFilter(currentCategory === targetCat ? 'ALL' : targetCat);
    });
  }

  // Difficulty Filter
  el.selectDifficulty.addEventListener('change', (e) => {
    currentDifficulty = e.target.value;
    renderQuestionsList();
  });

  // Unanswered Toggle
  el.checkUnanswered.addEventListener('change', (e) => {
    onlyUnanswered = e.target.checked;
    renderQuestionsList();
  });

  // Random Buttons
  el.btnPickRandom.addEventListener('click', pickRandomQuestion);
  el.btnRandomHeader.addEventListener('click', pickRandomQuestion);

  // Hints Toggle
  el.btnToggleHints.addEventListener('click', () => {
    const isHidden = el.hintsBody.classList.toggle('hidden');
    el.btnToggleHints.classList.toggle('open', !isHidden);
  });

  // Copy Code
  el.btnCopyCode.addEventListener('click', () => {
    const code = el.arenaCodeSnippet.textContent;
    navigator.clipboard.writeText(code).then(() => {
      showToast('Đã sao chép đoạn code vào clipboard!', 'success');
    });
  });

  // Answer Textarea
  el.answerTextarea.addEventListener('input', updateWordCount);

  // Editor Toolbar Snippets
  document.querySelectorAll('.toolbar-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const rawSnippet = btn.dataset.snippet;
      if (!rawSnippet) return;
      const snippet = rawSnippet.replace(/\\n/g, '\n');
      const start = el.answerTextarea.selectionStart;
      const end = el.answerTextarea.selectionEnd;
      const text = el.answerTextarea.value;
      el.answerTextarea.value = text.substring(0, start) + snippet + text.substring(end);
      el.answerTextarea.focus();
      updateWordCount();
    });
  });

  // Reset Answer
  el.btnResetAnswer.addEventListener('click', () => {
    if (!confirm('Bạn có chắc muốn xoá câu trả lời đang nhập?')) return;
    el.answerTextarea.value = '';
    el.resultCard.classList.add('hidden');
    updateWordCount();
    if (submissions[activeQuestionId]) {
      delete submissions[activeQuestionId];
      saveStoredData();
      updateStats();
      renderQuestionsList();
    }
  });

  // Peek Ideal Answer
  el.btnPeekIdeal.addEventListener('click', () => {
    const q = allQuestions.find(item => item.id === activeQuestionId);
    if (!q) return;
    renderEvaluationResult({
      score: submissions[q.id]?.result?.score || 0,
      summary: 'Đang xem trước đáp án chuẩn tham chiếu của dự án NET_ver1.',
      strengths: ['Đáp án chuẩn được trích xuất trực tiếp từ kiến trúc và tài liệu BUG-LOG.md.'],
      missingPoints: ['Hãy đối chiếu câu trả lời của bạn với các tiêu chí này.'],
      idealAnswer: q.idealAnswer,
      followUpQuestion: 'Hãy thử giải thích lại vấn đề này theo cấu trúc của đáp án chuẩn.'
    }, false);
    el.resultCard.scrollIntoView({ behavior: 'smooth' });
  });

  // Submit Answer
  el.btnSubmitAnswer.addEventListener('click', submitAnswer);

  // Settings Modal
  el.btnSettingsModal.addEventListener('click', openSettingsModal);
  el.btnCloseSettings.addEventListener('click', closeSettingsModal);
  el.btnCancelSettings.addEventListener('click', closeSettingsModal);
  el.btnSaveSettings.addEventListener('click', saveSettings);
  el.settingProvider.addEventListener('change', () => {
    const isGemini = el.settingProvider.value === 'gemini';
    el.groupGeminiKey.style.display = isGemini ? 'flex' : 'none';
    el.groupGeminiModel.style.display = isGemini ? 'flex' : 'none';
  });
  el.btnToggleKeyVis.addEventListener('click', () => {
    const isPass = el.settingGeminiKey.type === 'password';
    el.settingGeminiKey.type = isPass ? 'text' : 'password';
    el.btnToggleKeyVis.textContent = isPass ? 'Ẩn' : 'Hiện';
  });
}

// Start application
document.addEventListener('DOMContentLoaded', init);
