/**
 * PROGRAM COMPOSITOR RUNTIME (1920x1080 @ 60FPS)
 * Manages layer layout interpolation, ambient particles, chat stream rendering,
 * clock ticking, and safety gate layer enforcement.
 */

// IPC interface injected by preload or electron window
const ipc = (window as any).electronIpc || {
  on: (_channel: string, _cb: Function) => {},
  send: (_channel: string, _data?: any) => {},
};

let currentSafetyState: string = 'PROGRAM_SAFE';

// ============================================================================
// 1. AMBIENT PARTICLES (60FPS WebGL/Canvas2D Canvas)
// ============================================================================
const canvas = document.getElementById('particles-canvas') as HTMLCanvasElement;
const ctx = canvas?.getContext('2d');

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  alpha: number;
  color: string;
}

const particles: Particle[] = [];
const PARTICLE_COUNT = 45;

// Pre-rendered radial glowing sprites for zero-overhead 60 FPS particles
function createGlowSprite(color: string): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = 32;
  c.height = 32;
  const sCtx = c.getContext('2d');
  if (sCtx) {
    const grad = sCtx.createRadialGradient(16, 16, 0, 16, 16, 16);
    grad.addColorStop(0, color);
    grad.addColorStop(0.4, color);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    sCtx.fillStyle = grad;
    sCtx.fillRect(0, 0, 32, 32);
  }
  return c;
}

const goldSprite = createGlowSprite('#ffd700');
const whiteSprite = createGlowSprite('#ffffff');

function initParticles() {
  if (!canvas) return;
  particles.length = 0;
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    particles.push({
      x: Math.random() * 1920,
      y: Math.random() * 1080,
      vx: (Math.random() - 0.5) * 0.4,
      vy: -Math.random() * 0.6 - 0.2, // Drift upwards
      size: Math.random() * 2.5 + 1,
      alpha: Math.random() * 0.6 + 0.2,
      color: Math.random() > 0.3 ? 'gold' : 'white',
    });
  }
}

function renderParticles() {
  if (!ctx) return;
  ctx.clearRect(0, 0, 1920, 1080);

  for (const p of particles) {
    p.x += p.vx;
    p.y += p.vy;

    if (p.y < -10) p.y = 1090;
    if (p.x < -10) p.x = 1930;
    if (p.x > 1930) p.x = -10;

    ctx.globalAlpha = p.alpha;
    const sprite = p.color === 'gold' ? goldSprite : whiteSprite;
    const dim = p.size * 4;
    ctx.drawImage(sprite, p.x - dim / 2, p.y - dim / 2, dim, dim);
  }
  ctx.globalAlpha = 1.0;

  requestAnimationFrame(renderParticles);
}

initParticles();
renderParticles();

// ============================================================================
// 2. 24/7 STUDIO CLOCK
// ============================================================================
const clockEl = document.getElementById('studio-clock');
setInterval(() => {
  if (!clockEl) return;
  const now = new Date();
  const h = String(now.getHours()).padStart(2, '0');
  const m = String(now.getMinutes()).padStart(2, '0');
  const s = String(now.getSeconds()).padStart(2, '0');
  clockEl.innerText = `${h}:${m}:${s}`;
}, 1000);

// ============================================================================
// 3. LAYER POSITION & GEOMETRY UPDATER
// ============================================================================
const layerElements: Record<string, HTMLElement | null> = {
  background: document.getElementById('comp-bg'),
  logo: document.getElementById('comp-logo'),
  warning: document.getElementById('comp-warning'),
  timer: document.getElementById('comp-timer'),
  game: document.getElementById('comp-game'),
  chat: document.getElementById('comp-chat'),
  payment: document.getElementById('comp-payment'),
};

function applyLayerGeometry(layerKey: string, geom: any) {
  const el = layerElements[layerKey];
  if (!el || !geom) return;

  el.style.left = `${geom.x}px`;
  el.style.top = `${geom.y}px`;
  el.style.width = `${geom.width}px`;
  el.style.height = `${geom.height}px`;
  el.style.transform = `scale(${geom.scale || 1}) rotate(${geom.rotation || 0}deg)`;
  el.style.opacity = String(geom.opacity ?? 1);
  el.style.zIndex = String(geom.zIndex || 1);
  el.style.display = geom.visible ? '' : 'none';
}

function applyPositionPreset(preset: any) {
  if (!preset || !preset.layers) return;
  for (const [key, geom] of Object.entries(preset.layers)) {
    applyLayerGeometry(key, geom);
  }
}

// ============================================================================
// 4. CHAT STREAM RENDERER
// ============================================================================
const chatContainer = document.getElementById('chat-messages');

function appendChatMessage(msg: { user: string; text: string; vip?: number }) {
  if (!chatContainer) return;

  const row = document.createElement('div');
  row.className = 'chat-row';

  const vipBadge = msg.vip && msg.vip > 0 ? `<span class="vip-badge">VIP ${msg.vip}</span>` : '';
  const avatarUrl = `https://api.dicebear.com/7.x/bottts/svg?seed=${encodeURIComponent(msg.user)}`;

  row.innerHTML = `
    <img src="${avatarUrl}" class="chat-avatar" alt="avatar">
    <div class="chat-bubble">
      <div class="chat-user">
        ${vipBadge}
        <span>${escapeHtml(msg.user)}</span>
      </div>
      <div class="chat-msg">${escapeHtml(msg.text)}</div>
    </div>
  `;

  chatContainer.appendChild(row);

  // Keep bounded buffer (max 25 messages) for smooth performance
  while (chatContainer.children.length > 25) {
    chatContainer.removeChild(chatContainer.firstChild!);
  }

  chatContainer.scrollTop = chatContainer.scrollHeight;
}

function escapeHtml(str: string): string {
  return str.replace(/[&<>'"]/g, 
    tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag));
}

// ============================================================================
// 5. SAFETY GATE ENFORCEMENT
// ============================================================================
function updateSafetyState(state: string) {
  currentSafetyState = state;
  document.body.className = '';
  document.body.classList.add(state.toLowerCase().replace(/_/g, '-'));

  const standbyCard = document.getElementById('game-standby');
  const standbyTitle = document.getElementById('game-standby-title');
  const standbySub = document.getElementById('game-standby-sub');

  if (state === 'PROGRAM_READY') {
    if (standbyCard) standbyCard.style.display = 'none';
  } else if (state === 'PROGRAM_DEGRADED') {
    if (standbyCard) {
      standbyCard.style.display = 'flex';
      if (standbyTitle) standbyTitle.innerText = 'NGUỒN LIVE ĐANG KẾT NỐI LẠI';
      if (standbySub) standbySub.innerText = 'Tự động phục hồi luồng cược không gián đoạn chương trình...';
    }
  } else {
    // PROGRAM_SAFE or PROGRAM_AUTH_REQUIRED
    if (standbyCard) {
      standbyCard.style.display = 'flex';
      if (standbyTitle) standbyTitle.innerText = 'CHẾ ĐỘ AN TOÀN PHÁT SÓNG';
      if (standbySub) standbySub.innerText = 'Nguồn động đang được cách ly để bảo vệ an toàn luồng phát.';
    }
  }
}

// ============================================================================
// 6. IPC EVENT LISTENERS
// ============================================================================
ipc.on('set-safety-state', (_event: any, state: string) => {
  updateSafetyState(state);
});

ipc.on('set-position', (_event: any, preset: any) => {
  applyPositionPreset(preset);
});

ipc.on('new-chat-message', (_event: any, msg: any) => {
  appendChatMessage(msg);
});
