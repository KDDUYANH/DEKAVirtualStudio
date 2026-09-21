/**
 * DEKA BACKGROUND ENGINE - MULTI-LAYER COMPOSITOR
 * High-performance 60fps DOM/Canvas Compositor with GPU Acceleration
 */

class Compositor {
  constructor(containerId) {
    this.container = document.getElementById(containerId);
    this.scene = null;
    this.timerInterval = null;
  }

  render(scene) {
    this.scene = scene;

    // Apply Mode (Full vs Transparent Overlay)
    if (scene.mode === 'transparent') {
      document.body.classList.add('mode-transparent');
    } else {
      document.body.classList.remove('mode-transparent');
    }

    // Sort layers by zIndex ascending
    const sortedLayers = [...scene.layers].sort((a, b) => a.zIndex - b.zIndex);

    // Synchronize DOM elements
    const existingNodeIds = new Set();

    sortedLayers.forEach((layer) => {
      existingNodeIds.add(layer.id);
      let node = document.getElementById(layer.id);

      if (!node) {
        node = this.createLayerNode(layer);
        this.container.appendChild(node);
      } else {
        this.updateLayerNode(node, layer);
      }
    });

    // Remove obsolete layer nodes
    const currentNodes = Array.from(this.container.children);
    currentNodes.forEach((node) => {
      if (!existingNodeIds.has(node.id)) {
        this.container.removeChild(node);
      }
    });

    // Ensure timer updates if timer layer exists
    this.setupLiveTimer();
  }

  createLayerNode(layer) {
    const node = document.createElement('div');
    node.id = layer.id;
    node.className = `layer-node type-${layer.type}`;
    if (!layer.visible) node.classList.add('hidden');

    this.applyTransformAndStyles(node, layer);
    this.populateLayerContent(node, layer);
    return node;
  }

  updateLayerNode(node, layer) {
    // Visibility
    if (layer.visible) {
      node.classList.remove('hidden');
    } else {
      node.classList.add('hidden');
    }

    // Styles & Transform
    this.applyTransformAndStyles(node, layer);

    // Specific content updates
    if (layer.type === 'alert') {
      this.updateAlertContent(node, layer);
    } else if (layer.type === 'custom') {
      this.updateTickerContent(node, layer);
    }
  }

  applyTransformAndStyles(node, layer) {
    const t = layer.transform;
    const s = layer.style;

    node.style.left = `${t.x}%`;
    node.style.top = `${t.y}%`;
    node.style.width = `${t.width}%`;
    node.style.height = `${t.height}%`;
    node.style.zIndex = layer.zIndex;
    node.style.opacity = s.opacity;
    node.style.mixBlendMode = s.blendMode;

    let transformStr = `scale(${t.scale || 1})`;
    node.style.transform = transformStr;

    if (t.crop) {
      node.style.clipPath = `inset(${t.crop.top || 0}% ${t.crop.right || 0}% ${t.crop.bottom || 0}% ${t.crop.left || 0}%)`;
    } else {
      node.style.clipPath = 'none';
    }

    if (s.borderRadius) {
      node.style.borderRadius = `${s.borderRadius}px`;
    }
  }

  populateLayerContent(node, layer) {
    node.innerHTML = '';

    switch (layer.type) {
      case 'image':
      case 'logo': {
        const img = document.createElement('img');
        img.src = layer.source.url || '/assets/deka-logo.svg';
        img.onerror = () => {
          if (layer.source.fallbackUrl) {
            img.src = layer.source.fallbackUrl;
          }
        };
        node.appendChild(img);
        break;
      }

      case 'game':
      case 'chat':
      case 'browser': {
        const iframe = document.createElement('iframe');
        iframe.src = layer.source.url || 'about:blank';
        iframe.setAttribute('data-src', layer.source.url || '');
        iframe.setAttribute('allow', 'autoplay; camera; microphone; fullscreen');
        iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups');
        node.appendChild(iframe);
        break;
      }

      case 'alert': {
        this.updateAlertContent(node, layer);
        break;
      }

      case 'timer': {
        node.innerHTML = `
          <div class="timer-badge">LIVE</div>
          <div class="timer-text" id="live-timer-text">00:00:00</div>
        `;
        break;
      }

      case 'custom': {
        this.updateTickerContent(node, layer);
        break;
      }
    }
  }

  updateAlertContent(node, layer) {
    const c = layer.source.content || {};
    const severity = c.severity || 'warning';
    node.className = `layer-node type-alert severity-${severity}`;
    if (!layer.visible) node.classList.add('hidden');

    node.innerHTML = `
      <div class="alert-content">
        <div class="alert-title">${c.title || '🚨 THÔNG BÁO STUDIO'}</div>
        <div class="alert-message">${c.message || ''}</div>
      </div>
    `;
  }

  updateTickerContent(node, layer) {
    const text = layer.source.content?.tickerText || 'D-TEK STUDIO 24/7 BACKGROUND ENGINE';
    node.innerHTML = `<div class="ticker-track">${text}</div>`;
  }

  setupLiveTimer() {
    if (this.timerInterval) return;
    const updateTime = () => {
      const el = document.getElementById('live-timer-text');
      if (el) {
        const now = new Date();
        el.innerText = now.toTimeString().split(' ')[0];
      }
    };
    updateTime();
    this.timerInterval = setInterval(updateTime, 1000);
  }

  // Soft reload only dynamic layers (iframe) without refreshing the entire page
  softReloadDynamicLayers() {
    const iframes = this.container.querySelectorAll('iframe');
    iframes.forEach((iframe) => {
      const src = iframe.getAttribute('data-src') || iframe.src;
      console.log('[Compositor] Soft reloading layer iframe:', src);
      iframe.src = src;
    });
  }

  // Fallback when network is completely offline
  applyDegradedFallback() {
    const bgLayerNode = this.container.querySelector('.type-image img');
    if (bgLayerNode && bgLayerNode.src.includes('background-studio.svg')) {
      bgLayerNode.src = '/assets/background-fallback.svg';
    }
  }
}

window.Compositor = Compositor;
