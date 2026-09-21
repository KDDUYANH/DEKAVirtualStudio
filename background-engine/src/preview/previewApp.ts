/**
 * PREVIEW WORKSPACE OPERATOR LOGIC
 * Manages Operator UI state, IPC triggers for Login, Positions, Auto Move,
 * and real-time NDI & Safety Gate diagnostics.
 */

const ipc = (window as any).electronIpc || {
  on: (_ch: string, _cb: Function) => {},
  send: (_ch: string, _data?: any) => {},
};

// UI Elements
const dotAuth = document.getElementById('dot-auth');
const labelAuth = document.getElementById('label-auth');
const dotGame = document.getElementById('dot-game');
const labelGame = document.getElementById('label-game');
const dotChat = document.getElementById('dot-chat');
const labelChat = document.getElementById('label-chat');
const safetyBadge = document.getElementById('safety-gate-badge');

const authStatusText = document.getElementById('auth-status-text');
const btnOpenLogin = document.getElementById('btn-open-login');
const btnLogout = document.getElementById('btn-logout');

const btnPos1 = document.getElementById('btn-pos-1');
const btnPos2 = document.getElementById('btn-pos-2');
const btnPos3 = document.getElementById('btn-pos-3');

const btnSaveP1 = document.getElementById('btn-save-p1');
const btnSaveP2 = document.getElementById('btn-save-p2');
const btnSaveP3 = document.getElementById('btn-save-p3');

const automoveCurrent = document.getElementById('automove-current');
const automoveRemaining = document.getElementById('automove-remaining');
const automoveNext = document.getElementById('automove-next');
const automoveStatePill = document.getElementById('automove-state-pill');

const btnAutoStart = document.getElementById('btn-auto-start');
const btnAutoPause = document.getElementById('btn-auto-pause');
const btnAutoStop = document.getElementById('btn-auto-stop');
const btnAutoPrev = document.getElementById('btn-auto-prev');
const btnAutoNext = document.getElementById('btn-auto-next');
const chkAutoLoop = document.getElementById('chk-auto-loop') as HTMLInputElement;

const ndiReadyLabel = document.getElementById('ndi-ready-label');
const ndiStreamName = document.getElementById('ndi-stream-name');
const btnTestOutput = document.getElementById('btn-test-output');

const diagFps = document.getElementById('diag-fps');
const diagReceivers = document.getElementById('diag-receivers');
const diagUptime = document.getElementById('diag-uptime');

// ============================================================================
// 1. AUTHENTICATION TRIGGERS
// ============================================================================
btnOpenLogin?.addEventListener('click', () => {
  ipc.send('open-login');
});

btnLogout?.addEventListener('click', () => {
  if (confirm('Bạn có chắc chắn muốn đăng xuất tài khoản?')) {
    ipc.send('logout');
  }
});

// ============================================================================
// 2. POSITION SWITCHING & SAVING
// ============================================================================
function setActivePositionUi(pos: string) {
  btnPos1?.classList.toggle('active', pos === 'P1');
  btnPos2?.classList.toggle('active', pos === 'P2');
  btnPos3?.classList.toggle('active', pos === 'P3');
}

btnPos1?.addEventListener('click', () => {
  setActivePositionUi('P1');
  ipc.send('set-position', 'P1');
});

btnPos2?.addEventListener('click', () => {
  setActivePositionUi('P2');
  ipc.send('set-position', 'P2');
});

btnPos3?.addEventListener('click', () => {
  setActivePositionUi('P3');
  ipc.send('set-position', 'P3');
});

btnSaveP1?.addEventListener('click', () => {
  ipc.send('save-position', 'P1');
  alert('Đã lưu cấu hình hiện tại vào POSITION 1!');
});

btnSaveP2?.addEventListener('click', () => {
  ipc.send('save-position', 'P2');
  alert('Đã lưu cấu hình hiện tại vào POSITION 2!');
});

btnSaveP3?.addEventListener('click', () => {
  ipc.send('save-position', 'P3');
  alert('Đã lưu cấu hình hiện tại vào POSITION 3!');
});

// ============================================================================
// 3. AUTO MOVE CONTROLS
// ============================================================================
btnAutoStart?.addEventListener('click', () => ipc.send('automove-cmd', 'start'));
btnAutoPause?.addEventListener('click', () => ipc.send('automove-cmd', 'pause'));
btnAutoStop?.addEventListener('click', () => ipc.send('automove-cmd', 'stop'));
btnAutoPrev?.addEventListener('click', () => ipc.send('automove-cmd', 'previous'));
btnAutoNext?.addEventListener('click', () => ipc.send('automove-cmd', 'next'));

chkAutoLoop?.addEventListener('change', () => {
  ipc.send('automove-cmd', { action: 'set-loop', loop: chkAutoLoop.checked });
});

// ============================================================================
// 4. OUTPUT NDI TRIGGERS
// ============================================================================
btnTestOutput?.addEventListener('click', () => {
  ipc.send('test-output');
});

// ============================================================================
// 5. IPC TELEMETRY LISTENERS
// ============================================================================
ipc.on('safety-state-changed', (_e: any, data: any) => {
  if (!safetyBadge) return;
  const state = data.current;
  safetyBadge.className = 'safety-gate-badge';
  safetyBadge.classList.add(`badge-${state.toLowerCase().replace(/_/g, '-')}`);
  safetyBadge.innerText = state.replace(/_/g, ' ');
});

ipc.on('auth-status-changed', (_e: any, status: any) => {
  if (status.isAuthenticated) {
    if (dotAuth) dotAuth.className = 'status-dot green';
    if (labelAuth) labelAuth.innerText = `AUTH: ${status.username || 'OPERATOR'}`;
    if (authStatusText) {
      authStatusText.innerText = 'AUTHENTICATED (READY)';
      authStatusText.style.color = '#10b981';
    }
  } else {
    if (dotAuth) dotAuth.className = 'status-dot red';
    if (labelAuth) labelAuth.innerText = 'LOGIN REQUIRED';
    if (authStatusText) {
      authStatusText.innerText = 'LOGIN REQUIRED';
      authStatusText.style.color = '#ef4444';
    }
  }
});

ipc.on('game-state-changed', (_e: any, data: any) => {
  if (labelGame) labelGame.innerText = `GAME: ${data.state}`;
  if (dotGame) {
    if (data.state === 'LIVE' || data.state === 'READY') {
      dotGame.className = 'status-dot green';
    } else if (data.state === 'RECONNECTING' || data.state === 'BUFFERING') {
      dotGame.className = 'status-dot amber';
    } else {
      dotGame.className = 'status-dot red';
    }
  }
});

ipc.on('chat-state-changed', (_e: any, data: any) => {
  if (labelChat) labelChat.innerText = `CHAT: ${data.state}`;
  if (dotChat) {
    if (data.state === 'CONNECTED' || data.state === 'READY') {
      dotChat.className = 'status-dot green';
    } else if (data.state === 'RECONNECTING') {
      dotChat.className = 'status-dot amber';
    } else {
      dotChat.className = 'status-dot red';
    }
  }
});

ipc.on('automove-tick', (_e: any, data: any) => {
  if (automoveCurrent) automoveCurrent.innerText = data.currentPosition;
  if (automoveRemaining) automoveRemaining.innerText = `${data.timeRemainingSeconds}s`;
  if (automoveNext) automoveNext.innerText = data.nextPosition;
  if (automoveStatePill) {
    automoveStatePill.innerText = data.state;
    automoveStatePill.style.color = data.state === 'RUNNING' ? '#10b981' : (data.state === 'PAUSED' ? '#f59e0b' : '#9ca3af');
  }
  setActivePositionUi(data.currentPosition);
});

ipc.on('ndi-telemetry', (_e: any, data: any) => {
  if (ndiReadyLabel) {
    ndiReadyLabel.innerText = data.ndiLoaded ? 'NDI READY' : 'NDI FALLBACK';
    ndiReadyLabel.style.color = data.ndiLoaded ? '#10b981' : '#f59e0b';
  }
  if (ndiStreamName) ndiStreamName.innerText = data.streamName;
  if (diagFps) diagFps.innerText = `${data.fps.toFixed(1)}`;
  if (diagReceivers) diagReceivers.innerText = `${data.receivers}`;
});

ipc.on('app-telemetry', (_e: any, data: any) => {
  if (diagUptime) diagUptime.innerText = `${Math.floor(data.uptimeSeconds / 60)}m ${data.uptimeSeconds % 60}s`;
  if (diagFps && data.fps) diagFps.innerText = `${data.fps.toFixed(1)}`;
});
