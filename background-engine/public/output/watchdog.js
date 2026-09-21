/**
 * DEKA BACKGROUND ENGINE - AUTONOMOUS CLIENT WATCHDOG
 * Detects: Render Freeze, Iframe Crash, Network Stall, Media Stops
 * Recovers: Per-layer Soft Reload, Fallback Asset Injection, Zero-Downtime
 */

class ClientWatchdog {
  constructor(compositor) {
    this.compositor = compositor;
    this.currentFps = 60;
    this.droppedFrames = 0;
    this.lastFrameTime = performance.now();
    this.frameCount = 0;
    this.fpsTimer = performance.now();
    this.isFrozen = false;
    this.layerHealth = new Map();

    this.initFpsMonitor();
    this.initNetworkMonitor();
    this.startPeriodicHealthCheck();
  }

  initFpsMonitor() {
    const loop = (now) => {
      const delta = now - this.lastFrameTime;
      this.lastFrameTime = now;

      // Check for frame freeze (> 3000ms delta without rendering)
      if (delta > 3000 && !this.isFrozen) {
        console.warn(`[Watchdog] Frame freeze detected! Delta: ${delta.toFixed(0)}ms`);
        this.onRenderFreezeDetected();
      }

      this.frameCount++;
      if (now - this.fpsTimer >= 1000) {
        this.currentFps = this.frameCount;
        if (this.currentFps < 30) {
          this.droppedFrames += (60 - this.currentFps);
        }
        this.frameCount = 0;
        this.fpsTimer = now;
      }

      requestAnimationFrame(loop);
    };

    requestAnimationFrame(loop);
  }

  initNetworkMonitor() {
    window.addEventListener('online', () => {
      console.log('[Watchdog] Network online restored');
      document.body.classList.remove('degraded');
    });

    window.addEventListener('offline', () => {
      console.warn('[Watchdog] Network offline! Entering Degraded Mode');
      document.body.classList.add('degraded');
      this.compositor.applyDegradedFallback();
    });
  }

  onRenderFreezeDetected() {
    this.isFrozen = true;
    console.warn('[Watchdog] Executing soft recovery on dynamic layers...');
    
    // Attempt soft recovery of dynamic layers
    this.compositor.softReloadDynamicLayers();

    setTimeout(() => {
      this.isFrozen = false;
    }, 2000);
  }

  startPeriodicHealthCheck() {
    // Check all iframes every 10 seconds
    setInterval(() => {
      const iframes = document.querySelectorAll('iframe');
      iframes.forEach((iframe) => {
        try {
          // If iframe is loaded and accessible, verify it hasn't blanked out
          if (iframe.contentWindow && iframe.contentWindow.location.href === 'about:blank') {
            console.warn('[Watchdog] Detected blank iframe, triggering reload:', iframe.id);
            iframe.src = iframe.getAttribute('data-src') || iframe.src;
          }
        } catch (e) {
          // Cross-origin iframe is expected, cannot inspect directly, normal behavior
        }
      });
    }, 10000);
  }

  reportLayerStatus(layerId, status) {
    this.layerHealth.set(layerId, status);
  }

  getHealthSummary() {
    const summary = {};
    this.layerHealth.forEach((val, key) => {
      summary[key] = val;
    });
    return summary;
  }
}

window.ClientWatchdog = ClientWatchdog;
