import { Scene, Layer } from '../types.js';

export function createDefaultScene(tableId: string): Scene {
  const layers: Layer[] = [
    // LAYER 01: Base Background
    {
      id: `${tableId}-layer-bg`,
      name: 'Layer 01 - Studio Background',
      type: 'image',
      zIndex: 1,
      visible: true,
      locked: true,
      transform: {
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        scale: 1,
      },
      style: {
        opacity: 1.0,
        blendMode: 'normal',
      },
      source: {
        url: '/assets/background-studio.svg',
        fallbackUrl: '/assets/background-fallback.svg',
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 02: Web Game / Interactive Browser
    {
      id: `${tableId}-layer-game`,
      name: 'Layer 02 - Live Game Stream / Interactive Web',
      type: 'game',
      zIndex: 2,
      visible: true,
      locked: false,
      transform: {
        x: 5,
        y: 8,
        width: 65,
        height: 75,
        scale: 1,
      },
      style: {
        opacity: 1.0,
        blendMode: 'normal',
        borderRadius: 12,
      },
      source: {
        url: `/api/demo/game-widget?tableId=${tableId}`,
        refreshInterval: 0,
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 03: Live Chat & Comments
    {
      id: `${tableId}-layer-chat`,
      name: 'Layer 03 - Live Chat Feed',
      type: 'chat',
      zIndex: 3,
      visible: true,
      locked: false,
      transform: {
        x: 72,
        y: 15,
        width: 25,
        height: 68,
        scale: 1,
      },
      style: {
        opacity: 0.95,
        blendMode: 'normal',
        borderRadius: 12,
      },
      source: {
        url: `/api/demo/chat-widget?tableId=${tableId}`,
        refreshInterval: 0,
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 04: Emergency / Live Alert
    {
      id: `${tableId}-layer-alert`,
      name: 'Layer 04 - Alert & Breaking News',
      type: 'alert',
      zIndex: 4,
      visible: false, // Default hidden, triggered by operator
      locked: false,
      transform: {
        x: 20,
        y: 35,
        width: 60,
        height: 30,
        scale: 1,
      },
      style: {
        opacity: 1.0,
        blendMode: 'normal',
        borderRadius: 16,
      },
      source: {
        content: {
          title: '🚨 THÔNG BÁO STUDIO',
          message: 'Bắt đầu phiên mở thưởng đặc biệt!',
          severity: 'warning',
        },
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 05: Studio Logo & Watermark
    {
      id: `${tableId}-layer-logo`,
      name: 'Layer 05 - Studio Branding Logo',
      type: 'logo',
      zIndex: 5,
      visible: true,
      locked: true,
      transform: {
        x: 4,
        y: 3,
        width: 14,
        height: 7,
        scale: 1,
      },
      style: {
        opacity: 0.9,
        blendMode: 'screen',
      },
      source: {
        url: '/assets/deka-logo.svg',
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 06: Broadcast Countdown Timer / On-Air Clock
    {
      id: `${tableId}-layer-timer`,
      name: 'Layer 06 - On-Air Clock & Timer',
      type: 'timer',
      zIndex: 6,
      visible: true,
      locked: false,
      transform: {
        x: 82,
        y: 3,
        width: 15,
        height: 6,
        scale: 1,
      },
      style: {
        opacity: 1.0,
        blendMode: 'normal',
        borderRadius: 8,
      },
      source: {
        content: {
          format: 'HH:mm:ss',
          showSeconds: true,
          liveBadge: true,
        },
      },
      state: {
        status: 'healthy',
      },
    },

    // LAYER 07: Custom Graphics / Lower-Third Ticker
    {
      id: `${tableId}-layer-custom`,
      name: 'Layer 07 - Lower-Third Ticker Banner',
      type: 'custom',
      zIndex: 7,
      visible: true,
      locked: false,
      transform: {
        x: 0,
        y: 91,
        width: 100,
        height: 9,
        scale: 1,
      },
      style: {
        opacity: 0.95,
        blendMode: 'normal',
      },
      source: {
        content: {
          tickerText: '★ DEKA VIRTUAL STUDIO 24/7 BACKGROUND ENGINE ★ VMIX CEF READY ★ ZERO-DOWNTIME PERSISTENT SESSION ★',
          speed: 40,
        },
      },
      state: {
        status: 'healthy',
      },
    },
  ];

  return {
    tableId,
    mode: 'full', // 'full' or 'transparent'
    resolution: {
      width: 1920,
      height: 1080,
    },
    fps: 60,
    layers,
    lockedProduction: false,
    publishedAt: Date.now(),
    version: 1,
  };
}
