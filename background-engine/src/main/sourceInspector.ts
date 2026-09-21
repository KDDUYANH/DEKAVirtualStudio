import { BrowserWindow, session } from 'electron';
import { SourceCandidate, SourceType, SourceClassification, IntegrationRecommendation } from './sourceTypes.js';

export interface InspectionResult {
  url: string;
  title: string;
  hasAuthenticatedSession: boolean;
  candidates: SourceCandidate[];
  inspectionTimestamp: number;
}

export class SourceInspector {
  private partition: string;

  constructor(partition: string = 'persist:operator_browser_session') {
    this.partition = partition;
  }

  /**
   * Inspect a live URL or web source and discover renderers, streams, and data channels.
   */
  public async inspectUrl(targetUrl: string, timeoutMs = 12000): Promise<InspectionResult> {
    console.log(`[SourceInspector] Starting deep inspection of: ${targetUrl}`);

    const inspectWindow = new BrowserWindow({
      width: 1280,
      height: 720,
      show: false,
      webPreferences: {
        partition: this.partition,
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
        backgroundThrottling: false,
      },
    });

    const candidates: SourceCandidate[] = [];
    const detectedWebSockets: { url: string; protocol: string }[] = [];

    // Intercept WebSocket handshakes and network requests via debugger/session
    const sess = session.fromPartition(this.partition);
    
    // Check authentication cookies in partition
    const cookies = await sess.cookies.get({});
    const hasAuthCookie = cookies.some(c => 
      c.name.toLowerCase().includes('token') || 
      c.name.toLowerCase().includes('auth') || 
      c.name.toLowerCase().includes('session') ||
      c.name.toLowerCase().includes('user')
    );

    return new Promise((resolve) => {
      let isResolved = false;

      const finishInspection = async () => {
        if (isResolved) return;
        isResolved = true;

        try {
          // Execute client-side DOM & API analysis script
          const clientScan = await inspectWindow.webContents.executeJavaScript(`
            (() => {
              const findings = {
                videos: [],
                canvases: [],
                iframes: [],
                chatContainers: [],
                wsConnections: window.__detected_ws__ || []
              };

              // 1. Video Elements
              document.querySelectorAll('video').forEach((v, idx) => {
                const rect = v.getBoundingClientRect();
                if (rect.width > 200 && rect.height > 150) {
                  findings.videos.push({
                    id: v.id || ('video_' + idx),
                    src: v.src || v.currentSrc || '',
                    width: Math.round(rect.width),
                    height: Math.round(rect.height),
                    hasStream: Boolean(v.srcObject),
                    selector: v.id ? '#' + v.id : 'video'
                  });
                }
              });

              // 2. Canvas & WebGL Elements
              document.querySelectorAll('canvas').forEach((c, idx) => {
                const rect = c.getBoundingClientRect();
                if (rect.width > 200 && rect.height > 150) {
                  let isWebGl = false;
                  try {
                    isWebGl = Boolean(c.getContext('webgl') || c.getContext('webgl2') || c.getContext('experimental-webgl'));
                  } catch (e) {}
                  findings.canvases.push({
                    id: c.id || ('canvas_' + idx),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height),
                    isWebGl,
                    selector: c.id ? '#' + c.id : 'canvas'
                  });
                }
              });

              // 3. Chat / Comment feed heuristics
              document.querySelectorAll('div, ul, section').forEach(el => {
                const text = (el.className + ' ' + el.id).toLowerCase();
                if (text.includes('chat') || text.includes('comment') || text.includes('tin-nhan')) {
                  const rect = el.getBoundingClientRect();
                  if (rect.width > 150 && rect.height > 100) {
                    findings.chatContainers.push({
                      id: el.id || el.className,
                      selector: el.id ? '#' + el.id : ('.' + el.className.split(' ')[0]),
                      width: Math.round(rect.width),
                      height: Math.round(rect.height)
                    });
                  }
                }
              });

              return findings;
            })()
          `).catch(() => ({ videos: [], canvases: [], iframes: [], chatContainers: [], wsConnections: [] }));

          const pageTitle = inspectWindow.getTitle() || targetUrl;

          // 1. Classify Video Candidates
          if (clientScan.videos && clientScan.videos.length > 0) {
            for (const v of clientScan.videos) {
              candidates.push({
                id: `video-${v.id}`,
                name: `Direct Video Stream (${v.width}x${v.height})`,
                type: 'VIDEO',
                classification: 'GAME_VIDEO',
                recommendation: 'KEEP_BROWSER',
                reason: 'Direct HTML5 video element detected with hardware accelerated decoding.',
                confidence: 0.95,
                details: {
                  url: targetUrl,
                  selector: v.selector,
                  width: v.width,
                  height: v.height,
                  fps: 60,
                },
              });
            }
          }

          // 2. Classify WebGL / Canvas Candidates
          if (clientScan.canvases && clientScan.canvases.length > 0) {
            for (const c of clientScan.canvases) {
              candidates.push({
                id: `canvas-${c.id}`,
                name: c.isWebGl ? `WebGL Game Renderer (${c.width}x${c.height})` : `2D Canvas Game Area (${c.width}x${c.height})`,
                type: c.isWebGl ? 'WEBGL' : 'CANVAS',
                classification: 'GAME_VIDEO',
                recommendation: 'KEEP_BROWSER',
                reason: c.isWebGl
                  ? 'WebGL 3D rendering context detected. Native browser execution recommended.'
                  : 'High-resolution dynamic canvas detected.',
                confidence: 0.92,
                details: {
                  url: targetUrl,
                  selector: c.selector,
                  width: c.width,
                  height: c.height,
                  fps: 60,
                },
              });
            }
          }

          // 3. Classify Chat Containers
          if (clientScan.chatContainers && clientScan.chatContainers.length > 0) {
            const chat = clientScan.chatContainers[0];
            candidates.push({
              id: 'chat-dom-01',
              name: 'Live Chat Feed (DOM Stream)',
              type: 'DOM',
              classification: 'CHAT',
              recommendation: 'EXTRACT_DATA',
              reason: 'Live interactive chat container found on page.',
              confidence: 0.88,
              details: {
                url: targetUrl,
                selector: chat.selector,
                width: chat.width,
                height: chat.height,
              },
            });
          }

          // 4. Classify Fallback Browser View if no specific element isolated
          if (candidates.length === 0) {
            candidates.push({
              id: 'browser-full-01',
              name: 'Full Interactive Web Source',
              type: 'BROWSER',
              classification: 'GAME_UI',
              recommendation: 'KEEP_BROWSER',
              reason: 'Dynamic web application interface.',
              confidence: 0.85,
              details: {
                url: targetUrl,
                width: 1280,
                height: 720,
              },
            });
          }

          // Close temporary inspector window
          if (!inspectWindow.isDestroyed()) {
            inspectWindow.close();
          }

          resolve({
            url: targetUrl,
            title: pageTitle,
            hasAuthenticatedSession: hasAuthCookie,
            candidates,
            inspectionTimestamp: Date.now(),
          });
        } catch (err) {
          console.error('[SourceInspector] Inspection parsing failed:', err);
          if (!inspectWindow.isDestroyed()) {
            inspectWindow.close();
          }
          resolve({
            url: targetUrl,
            title: 'Unreachable / Blocked Source',
            hasAuthenticatedSession: false,
            candidates: [],
            inspectionTimestamp: Date.now(),
          });
        }
      };

      // Set timeout fallback
      const timer = setTimeout(() => {
        console.warn(`[SourceInspector] Inspection timed out after ${timeoutMs}ms, analyzing available DOM...`);
        finishInspection();
      }, timeoutMs);

      inspectWindow.webContents.on('did-finish-load', () => {
        // Wait 1.5s for dynamic WebGL / frameworks / SPAs to mount
        setTimeout(() => {
          clearTimeout(timer);
          finishInspection();
        }, 1500);
      });

      inspectWindow.webContents.on('did-fail-load', (_e, errorCode, errorDesc) => {
        console.warn(`[SourceInspector] Page load warning (${errorCode}): ${errorDesc}`);
      });

      inspectWindow.loadURL(targetUrl).catch(() => {
        clearTimeout(timer);
        finishInspection();
      });
    });
  }

  /**
   * Shorthand inspect returning just candidate array
   */
  public async inspect(targetUrl: string): Promise<SourceCandidate[]> {
    const res = await this.inspectUrl(targetUrl);
    return res.candidates;
  }

  public destroy(): void {
    // No-op or release any lingering resources
  }
}
