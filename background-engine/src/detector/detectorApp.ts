declare global {
  interface Window {
    detectorIpc: {
      send: (channel: string, data?: any) => void;
      invoke: (channel: string, data?: any) => Promise<any>;
    };
  }
}

interface DiscoveredCandidate {
  id: string;
  type: string;
  label: string;
  selector?: string;
  endpoint?: string;
  confidence: number;
  recommendation: 'KEEP_BROWSER' | 'EXTRACT_DATA' | 'DIRECT_STREAM' | 'DOM_ISOLATE';
  details?: any;
}

document.addEventListener('DOMContentLoaded', () => {
  const urlInput = document.getElementById('urlInput') as HTMLInputElement;
  const btnScan = document.getElementById('btnScan') as HTMLButtonElement;
  const btnOpenBrowser = document.getElementById('btnOpenBrowser') as HTMLButtonElement;
  const btnCheckCookies = document.getElementById('btnCheckCookies') as HTMLButtonElement;
  const sessionStatus = document.getElementById('sessionStatus') as HTMLElement;

  const candidatesList = document.getElementById('candidatesList') as HTMLElement;
  const candidateCountBadge = document.getElementById('candidateCountBadge') as HTMLElement;

  const logTerminal = document.getElementById('logTerminal') as HTMLElement;
  const btnClearLog = document.getElementById('btnClearLog') as HTMLButtonElement;

  const previewScreen = document.getElementById('previewScreen') as HTMLElement;
  const teleType = document.getElementById('teleType') as HTMLElement;
  const teleLatency = document.getElementById('teleLatency') as HTMLElement;
  const teleConfidence = document.getElementById('teleConfidence') as HTMLElement;
  const teleRec = document.getElementById('teleRec') as HTMLElement;

  const adapterId = document.getElementById('adapterId') as HTMLInputElement;
  const adapterName = document.getElementById('adapterName') as HTMLInputElement;
  const adapterTarget = document.getElementById('adapterTarget') as HTMLInputElement;
  const adapterKind = document.getElementById('adapterKind') as HTMLSelectElement;
  const adapterPos = document.getElementById('adapterPos') as HTMLSelectElement;
  const btnExportAdapter = document.getElementById('btnExportAdapter') as HTMLButtonElement;
  const exportStatus = document.getElementById('exportStatus') as HTMLElement;

  let candidates: DiscoveredCandidate[] = [];
  let selectedCandidate: DiscoveredCandidate | null = null;

  function appendLog(text: string, level: 'INFO' | 'WARN' | 'SUCCESS' | 'PACKET' = 'INFO') {
    const time = new Date().toLocaleTimeString();
    const colorMap = {
      INFO: '#38bdf8',
      WARN: '#f59e0b',
      SUCCESS: '#34d399',
      PACKET: '#a78bfa',
    };
    const color = colorMap[level] || '#ffffff';
    const entry = document.createElement('div');
    entry.innerHTML = `<span style="color:#6b7280;">[${time}]</span> <span style="color:${color};font-weight:bold;">[${level}]</span> ${text}`;
    logTerminal.appendChild(entry);
    logTerminal.scrollTop = logTerminal.scrollHeight;
  }

  btnClearLog.addEventListener('click', () => {
    logTerminal.innerHTML = '';
    appendLog('Đã dọn sạch nhật ký.', 'INFO');
  });

  // 1. Quét sâu giao thức URL
  btnScan.addEventListener('click', async () => {
    const url = urlInput.value.trim();
    if (!url) {
      appendLog('URL không hợp lệ. Vui lòng nhập URL hợp lệ.', 'WARN');
      return;
    }

    btnScan.disabled = true;
    btnScan.innerHTML = '<span>⏳</span> ĐANG PHÂN TÍCH...';
    appendLog(`Bắt đầu thanh tra nguồn: ${url}`, 'INFO');

    try {
      const result = await window.detectorIpc.invoke('inspect-url', { url });
      appendLog(`Thanh tra hoàn tất. Đã quét giao thức, tìm thấy: ${result.candidates?.length || 0} thành phần.`, 'SUCCESS');

      candidates = result.candidates || [];
      candidateCountBadge.textContent = `${candidates.length} MỤC`;
      candidateCountBadge.className = 'badge badge-green';

      renderCandidates();
      if (candidates.length > 0) {
        selectCandidate(candidates[0]);
      }
    } catch (err: any) {
      appendLog(`Lỗi khi quét: ${err.message}`, 'WARN');
    } finally {
      btnScan.disabled = false;
      btnScan.innerHTML = '<span>🔍</span> QUÉT SÂU GIAO THỨC';
    }
  });

  // 2. Mở trình duyệt tương tác đăng nhập
  btnOpenBrowser.addEventListener('click', () => {
    const url = urlInput.value.trim() || 'https://google.com';
    appendLog(`Mở trình duyệt đăng nhập tương tác với partition: persist:operator_browser_session`, 'INFO');
    window.detectorIpc.send('open-interactive-browser', url);
  });

  // 3. Kiểm tra Cookies & Phiên
  btnCheckCookies.addEventListener('click', async () => {
    try {
      const info = await window.detectorIpc.invoke('get-session-cookies');
      appendLog(`Kiểm tra phiên: ${info.cookieCount} cookies trên ${info.domains.length} tên miền.`, 'INFO');
      if (info.hasAuthCookie) {
        sessionStatus.textContent = `ĐÃ ĐĂNG NHẬP (${info.cookieCount} COOKIES)`;
        sessionStatus.className = 'badge badge-green';
        appendLog('Đã phát hiện token/auth cookie trong phiên lưu trữ.', 'SUCCESS');
      } else {
        sessionStatus.textContent = `PHIÊN MỞ (${info.cookieCount} COOKIES)`;
        sessionStatus.className = 'badge badge-blue';
      }
    } catch (err: any) {
      appendLog(`Lỗi kiểm tra session: ${err.message}`, 'WARN');
    }
  });

  function renderCandidates() {
    candidatesList.innerHTML = '';
    if (candidates.length === 0) {
      candidatesList.innerHTML = `
        <div style="padding: 24px; text-align: center; color: var(--text-muted); font-size: 12px;">
          Không phát hiện thành phần tương thích nào. Thử đăng nhập trên trình duyệt trước.
        </div>
      `;
      return;
    }

    candidates.forEach((cand, idx) => {
      const card = document.createElement('div');
      card.className = `candidate-card ${selectedCandidate?.id === cand.id ? 'active' : ''}`;
      
      const badgeClass = cand.confidence > 0.7 ? 'badge-green' : (cand.confidence > 0.4 ? 'badge-blue' : 'badge-gray');
      
      card.innerHTML = `
        <div class="card-top">
          <span style="font-weight: 800; font-size: 13px; color: #fff;">${idx + 1}. ${cand.label || cand.type}</span>
          <span class="badge ${badgeClass}">${Math.round(cand.confidence * 100)}% TIN CẬY</span>
        </div>
        <div style="font-size: 11px; color: var(--text-muted); font-family: 'JetBrains Mono', monospace; word-break: break-all;">
          ${cand.selector || cand.endpoint || 'Toàn bộ cửa sổ / Canvas'}
        </div>
        <div style="display: flex; gap: 6px; margin-top: 4px;">
          <span class="badge badge-gray">${cand.type}</span>
          <span class="badge badge-blue">${cand.recommendation}</span>
        </div>
      `;

      card.addEventListener('click', () => selectCandidate(cand));
      candidatesList.appendChild(card);
    });
  }

  function selectCandidate(cand: DiscoveredCandidate) {
    selectedCandidate = cand;
    renderCandidates();

    // Cập nhật telemetry
    teleType.textContent = cand.type;
    teleLatency.textContent = cand.type.includes('WEBSOCKET') ? '8-15 ms' : '16-33 ms';
    teleConfidence.textContent = `${Math.round(cand.confidence * 100)}%`;
    teleRec.textContent = cand.recommendation;

    // Cập nhật cấu hình adapter
    adapterId.value = cand.id || `detected-${Date.now()}`;
    adapterName.value = cand.label || `Nguồn ${cand.type}`;
    adapterTarget.value = cand.selector || cand.endpoint || urlInput.value;

    if (cand.type.includes('WEBSOCKET')) {
      adapterKind.value = 'WEBSOCKET_DATA';
    } else if (cand.type.includes('STREAM') || cand.type.includes('VIDEO')) {
      adapterKind.value = 'STREAM_RELAY';
    } else {
      adapterKind.value = 'BROWSER_CAPTURE';
    }

    // Cập nhật khung xem trước
    updatePreview(cand);
  }

  function updatePreview(cand: DiscoveredCandidate) {
    previewScreen.innerHTML = '';
    const container = document.createElement('div');
    container.style.display = 'flex';
    container.style.flexDirection = 'column';
    container.style.alignItems = 'center';
    container.style.justifyContent = 'center';
    container.style.gap = '8px';
    container.style.padding = '12px';

    const icon = cand.type.includes('VIDEO') ? '📹' : (cand.type.includes('WEBSOCKET') ? '⚡' : '🖥️');
    container.innerHTML = `
      <div style="font-size: 40px;">${icon}</div>
      <div style="font-size: 14px; font-weight: 800; color: #fff;">${cand.label || cand.type}</div>
      <div style="font-size: 11px; color: var(--text-muted); font-family: 'JetBrains Mono', monospace; text-align: center;">
        Target: ${cand.selector || cand.endpoint || urlInput.value}
      </div>
      <div style="display: flex; gap: 8px; margin-top: 6px;">
        <span class="badge badge-green">TƯƠNG THÍCH 100%</span>
        <span class="badge badge-blue">NDI READY</span>
      </div>
    `;
    previewScreen.appendChild(container);
  }

  // 4. Xuất adapter sang Background Engine
  btnExportAdapter.addEventListener('click', async () => {
    const config = {
      id: adapterId.value.trim(),
      name: adapterName.value.trim(),
      target: adapterTarget.value.trim(),
      kind: adapterKind.value,
      defaultPosition: adapterPos.value,
      url: urlInput.value.trim(),
      timestamp: Date.now(),
    };

    appendLog(`Đang xuất cấu hình adapter [${config.name}] sang Background Engine...`, 'INFO');
    try {
      const res = await window.detectorIpc.invoke('export-adapter-to-engine', config);
      if (res.success) {
        exportStatus.textContent = `Đã xuất adapter thành công vào cấu hình Background Engine (Tổng: ${res.count} nguồn)!`;
        appendLog(`Đã xuất cấu hình thành công vào config.json của Background Engine. Engine sẽ tự động nhận diện.`, 'SUCCESS');
        setTimeout(() => {
          exportStatus.textContent = '';
        }, 4000);
      }
    } catch (err: any) {
      exportStatus.textContent = `Lỗi khi xuất: ${err.message}`;
      exportStatus.style.color = 'var(--red)';
      appendLog(`Lỗi xuất adapter: ${err.message}`, 'WARN');
    }
  });

  // Tự động kiểm tra cookies khi khởi động
  setTimeout(() => {
    btnCheckCookies.click();
  }, 500);
});
