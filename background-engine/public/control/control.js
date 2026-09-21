/**
 * DEKA BACKGROUND ENGINE - OPERATOR CONTROL PLANE LOGIC
 */

class ControlPlane {
  constructor() {
    this.currentTableId = this.getTableFromUrl() || 'table-01';
    this.scene = null;
    this.selectedLayerId = null;
    this.ws = null;
    this.uptimeSeconds = 0;

    this.initElements();
    this.initTableNav();
    this.initWebSocket();
    this.fetchScene();
    this.initEventHandlers();
  }

  getTableFromUrl() {
    const parts = window.location.pathname.split('/').filter(Boolean);
    return parts[1] || 'table-01';
  }

  initElements() {
    this.previewFrame = document.getElementById('preview-frame');
    this.layersList = document.getElementById('layers-list');
    this.lockBtn = document.getElementById('btn-lock');
    this.modeBtn = document.getElementById('btn-mode');
    this.openOutputBtn = document.getElementById('btn-open-output');
    this.copyUrlBtn = document.getElementById('btn-copy-url');
    this.btnTriggerAlert = document.getElementById('btn-trigger-alert');
    this.btnClearAlert = document.getElementById('btn-clear-alert');
    this.btnReloadAll = document.getElementById('btn-reload-all');

    // Telemetry Elements
    this.statFps = document.getElementById('stat-fps');
    this.statLayers = document.getElementById('stat-layers');
    this.statDropped = document.getElementById('stat-dropped');
    this.statUptime = document.getElementById('stat-uptime');
  }

  initTableNav() {
    const pills = document.querySelectorAll('.table-pill');
    pills.forEach((pill) => {
      pill.addEventListener('click', () => {
        pills.forEach((p) => p.classList.remove('active'));
        pill.classList.add('active');
        this.switchTable(pill.dataset.table);
      });
    });
  }

  switchTable(newTableId) {
    this.currentTableId = newTableId;
    window.history.pushState({}, '', `/control/${newTableId}`);
    this.fetchScene();
    this.initWebSocket(); // Rebind room
  }

  initWebSocket() {
    if (this.ws) {
      this.ws.close();
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    this.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);

    this.ws.onopen = () => {
      console.log('[Control] Connected to Gateway');
      this.ws.send(
        JSON.stringify({
          type: 'auth:handshake',
          tableId: this.currentTableId,
          payload: { clientType: 'control' },
          timestamp: Date.now(),
        })
      );
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'auth:ack' && msg.payload?.scene) {
          this.updateScene(msg.payload.scene);
        } else if (msg.type === 'state:sync' && msg.payload) {
          this.updateScene(msg.payload);
        } else if (msg.type === 'telemetry:report' && msg.payload) {
          this.updateTelemetry(msg.payload);
        } else if (msg.type === 'state:lock_toggle') {
          if (this.scene) {
            this.scene.lockedProduction = msg.payload.locked;
            this.applyLockUI(this.scene.lockedProduction);
          }
        }
      } catch (err) {
        console.error('[Control] WS Parse error:', err);
      }
    };
  }

  async fetchScene() {
    try {
      const res = await fetch(`/api/scene/${this.currentTableId}`);
      const data = await res.json();
      if (data.success && data.scene) {
        this.updateScene(data.scene);
      }
    } catch (err) {
      console.error('[Control] Failed to fetch scene:', err);
    }
  }

  updateScene(scene) {
    this.scene = scene;

    // Update Preview Frame src
    const previewUrl = `/output/${this.currentTableId}?mode=${scene.mode}&t=${Date.now()}`;
    if (this.previewFrame.src !== window.location.origin + previewUrl) {
      this.previewFrame.src = previewUrl;
    }

    // Update Mode Button
    this.modeBtn.innerText = scene.mode === 'transparent' ? 'MODE: TRANSPARENT (ALPHA)' : 'MODE: FULL BACKGROUND';

    // Update Lock State
    this.applyLockUI(scene.lockedProduction);

    // Render Layers List
    this.renderLayersList();

    // Update Selected Layer Inspector
    if (!this.selectedLayerId && scene.layers.length > 0) {
      this.selectedLayerId = scene.layers[0].id;
    }
    this.populateInspector();
  }

  renderLayersList() {
    this.layersList.innerHTML = '';
    // Display sorted by Z-Index descending (top layers first)
    const sorted = [...this.scene.layers].sort((a, b) => b.zIndex - a.zIndex);

    sorted.forEach((layer) => {
      const item = document.createElement('div');
      item.className = `layer-item ${layer.id === this.selectedLayerId ? 'selected' : ''}`;
      item.onclick = () => {
        this.selectedLayerId = layer.id;
        this.renderLayersList();
        this.populateInspector();
      };

      item.innerHTML = `
        <div class="layer-info">
          <span class="layer-zbadge">Z-${layer.zIndex.toString().padStart(2, '0')}</span>
          <span class="layer-name">${layer.name}</span>
        </div>
        <div class="layer-actions">
          <button class="icon-btn ${layer.visible ? 'active' : ''}" title="Toggle Visibility" onclick="event.stopPropagation(); window.controlPlane.toggleVisibility('${layer.id}')">
            ${layer.visible ? '👁️' : '🕶️'}
          </button>
          <button class="icon-btn" title="Move Up" onclick="event.stopPropagation(); window.controlPlane.moveLayer('${layer.id}', -1)">▲</button>
          <button class="icon-btn" title="Move Down" onclick="event.stopPropagation(); window.controlPlane.moveLayer('${layer.id}', 1)">▼</button>
          <button class="icon-btn" title="Reload Layer" onclick="event.stopPropagation(); window.controlPlane.reloadLayer('${layer.id}')">🔄</button>
        </div>
      `;
      this.layersList.appendChild(item);
    });

    this.statLayers.innerText = this.scene.layers.filter(l => l.visible).length;
  }

  populateInspector() {
    if (!this.scene) return;
    const layer = this.scene.layers.find((l) => l.id === this.selectedLayerId);
    if (!layer) return;

    document.getElementById('insp-name').value = layer.name;
    document.getElementById('insp-x').value = layer.transform.x;
    document.getElementById('insp-y').value = layer.transform.y;
    document.getElementById('insp-w').value = layer.transform.width;
    document.getElementById('insp-h').value = layer.transform.height;
    document.getElementById('insp-scale').value = layer.transform.scale || 1;
    document.getElementById('insp-opacity').value = layer.style.opacity;
    document.getElementById('insp-blend').value = layer.style.blendMode || 'normal';
    document.getElementById('insp-url').value = layer.source.url || '';
  }

  saveInspectorChanges() {
    if (!this.scene || !this.selectedLayerId) return;
    if (this.scene.lockedProduction) {
      alert('Production is LOCKED. Please unlock before editing.');
      return;
    }

    const payload = {
      transform: {
        x: parseFloat(document.getElementById('insp-x').value),
        y: parseFloat(document.getElementById('insp-y').value),
        width: parseFloat(document.getElementById('insp-w').value),
        height: parseFloat(document.getElementById('insp-h').value),
        scale: parseFloat(document.getElementById('insp-scale').value),
      },
      style: {
        opacity: parseFloat(document.getElementById('insp-opacity').value),
        blendMode: document.getElementById('insp-blend').value,
      },
      source: {
        url: document.getElementById('insp-url').value,
      },
    };

    fetch(`/api/scene/${this.currentTableId}/layer/${this.selectedLayerId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
  }

  toggleVisibility(layerId) {
    if (this.scene.lockedProduction) return;
    const layer = this.scene.layers.find((l) => l.id === layerId);
    if (!layer) return;

    fetch(`/api/scene/${this.currentTableId}/layer/${layerId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ visible: !layer.visible }),
    });
  }

  moveLayer(layerId, direction) {
    if (this.scene.lockedProduction) return;
    const sorted = [...this.scene.layers].sort((a, b) => a.zIndex - b.zIndex);
    const idx = sorted.findIndex((l) => l.id === layerId);
    if (idx === -1) return;

    const targetIdx = idx + direction;
    if (targetIdx < 0 || targetIdx >= sorted.length) return;

    const temp = sorted[idx];
    sorted[idx] = sorted[targetIdx];
    sorted[targetIdx] = temp;

    const orderedIds = sorted.map((l) => l.id);
    fetch(`/api/scene/${this.currentTableId}/reorder`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderedLayerIds: orderedIds }),
    });
  }

  reloadLayer(layerId) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(
        JSON.stringify({
          type: 'action:reload_layer',
          tableId: this.currentTableId,
          payload: { layerId },
          timestamp: Date.now(),
        })
      );
    }
  }

  applyLockUI(locked) {
    if (locked) {
      document.body.classList.add('production-locked');
      this.lockBtn.classList.add('locked');
      this.lockBtn.innerHTML = '🔒 LOCKED (CLICK TO UNLOCK)';
    } else {
      document.body.classList.remove('production-locked');
      this.lockBtn.classList.remove('locked');
      this.lockBtn.innerHTML = '🔓 UNLOCKED (CLICK TO LOCK)';
    }
  }

  toggleProductionLock() {
    const targetState = !this.scene.lockedProduction;
    fetch(`/api/scene/${this.currentTableId}/lock`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ locked: targetState }),
    });
  }

  toggleMode() {
    if (this.scene.lockedProduction) {
      alert('Production is LOCKED. Please unlock before switching mode.');
      return;
    }
    const targetMode = this.scene.mode === 'full' ? 'transparent' : 'full';
    fetch(`/api/scene/${this.currentTableId}/mode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode: targetMode }),
    });
  }

  updateTelemetry(tel) {
    if (this.statFps) this.statFps.innerText = tel.fps || 60;
    if (this.statDropped) this.statDropped.innerText = tel.droppedFrames || 0;
    if (this.statUptime) {
      const m = Math.floor(tel.uptimeSeconds / 60);
      const s = tel.uptimeSeconds % 60;
      this.statUptime.innerText = `${m}m ${s}s`;
    }
  }

  initEventHandlers() {
    this.lockBtn.onclick = () => this.toggleProductionLock();
    this.modeBtn.onclick = () => this.toggleMode();

    this.openOutputBtn.onclick = () => {
      window.open(`/output/${this.currentTableId}?mode=${this.scene?.mode || 'full'}`, '_blank');
    };

    this.copyUrlBtn.onclick = () => {
      const url = `${window.location.origin}/output/${this.currentTableId}?mode=${this.scene?.mode || 'full'}`;
      navigator.clipboard.writeText(url).then(() => {
        alert(`Copied vMix Browser Input URL:\n${url}`);
      });
    };

    this.btnTriggerAlert.onclick = () => {
      const title = prompt('Tiêu đề thông báo:', '🚨 THÔNG BÁO STUDIO ON-AIR');
      if (!title) return;
      const message = prompt('Nội dung:', 'Bắt đầu đợt quay thưởng jackpot!');
      fetch(`/api/scene/${this.currentTableId}/alert`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, message, severity: 'warning' }),
      });
    };

    this.btnClearAlert.onclick = () => {
      fetch(`/api/scene/${this.currentTableId}/alert`, { method: 'DELETE' });
    };

    this.btnReloadAll.onclick = () => {
      if (this.previewFrame) {
        this.previewFrame.src = this.previewFrame.src;
      }
    };

    // Auto-save form inputs on change
    const inputs = ['insp-x', 'insp-y', 'insp-w', 'insp-h', 'insp-scale', 'insp-opacity', 'insp-blend', 'insp-url'];
    inputs.forEach((id) => {
      const el = document.getElementById(id);
      if (el) {
        el.oninput = () => this.saveInspectorChanges();
      }
    });
  }
}

window.controlPlane = new ControlPlane();
