import { EngineConfig, PositionPreset } from './types.js';

export const DEFAULT_P1: PositionPreset = {
  id: 'P1',
  name: 'POSITION 1 — SPLIT SOURCE & LIVE CHAT',
  durationSeconds: 30,
  layers: {
    background: { x: 0, y: 0, width: 1920, height: 1080, scale: 1, opacity: 1, rotation: 0, zIndex: 1, visible: true, locked: true, fitMode: 'cover' },
    logo: { x: 50, y: 35, width: 220, height: 65, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    warning: { x: 300, y: 38, width: 1200, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    timer: { x: 1530, y: 35, width: 340, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    game: { x: 50, y: 120, width: 1280, height: 720, scale: 1, opacity: 1, rotation: 0, zIndex: 10, visible: true, locked: false, fitMode: 'contain' },
    chat: { x: 1360, y: 120, width: 510, height: 910, scale: 1, opacity: 1, rotation: 0, zIndex: 12, visible: true, locked: false, fitMode: 'contain' },
    payment: { x: 50, y: 865, width: 1280, height: 165, scale: 1, opacity: 1, rotation: 0, zIndex: 15, visible: true, locked: false, fitMode: 'contain' },
  },
};

export const DEFAULT_P2: PositionPreset = {
  id: 'P2',
  name: 'POSITION 2 — BRAND WARNING FOCUS & COMPACT CHAT',
  durationSeconds: 20,
  layers: {
    background: { x: 0, y: 0, width: 1920, height: 1080, scale: 1, opacity: 1, rotation: 0, zIndex: 1, visible: true, locked: true, fitMode: 'cover' },
    logo: { x: 50, y: 35, width: 220, height: 65, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    warning: { x: 300, y: 38, width: 1200, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    timer: { x: 1530, y: 35, width: 340, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    game: { x: 50, y: 120, width: 1100, height: 620, scale: 1, opacity: 1, rotation: 0, zIndex: 10, visible: true, locked: false, fitMode: 'contain' },
    chat: { x: 1180, y: 440, width: 690, height: 590, scale: 1, opacity: 1, rotation: 0, zIndex: 12, visible: true, locked: false, fitMode: 'contain' },
    payment: { x: 50, y: 770, width: 1100, height: 260, scale: 1, opacity: 1, rotation: 0, zIndex: 15, visible: true, locked: false, fitMode: 'contain' },
  },
};

export const DEFAULT_P3: PositionPreset = {
  id: 'P3',
  name: 'POSITION 3 — FULL ACTION SHOWCASE & SPEED NẠP',
  durationSeconds: 30,
  layers: {
    background: { x: 0, y: 0, width: 1920, height: 1080, scale: 1, opacity: 1, rotation: 0, zIndex: 1, visible: true, locked: true, fitMode: 'cover' },
    logo: { x: 50, y: 35, width: 220, height: 65, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    warning: { x: 300, y: 38, width: 1200, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    timer: { x: 1530, y: 35, width: 340, height: 55, scale: 1, opacity: 1, rotation: 0, zIndex: 20, visible: true, locked: true, fitMode: 'contain' },
    game: { x: 50, y: 120, width: 1360, height: 765, scale: 1, opacity: 1, rotation: 0, zIndex: 10, visible: true, locked: false, fitMode: 'contain' },
    chat: { x: 1440, y: 120, width: 430, height: 910, scale: 1, opacity: 1, rotation: 0, zIndex: 12, visible: true, locked: false, fitMode: 'contain' },
    payment: { x: 50, y: 910, width: 1360, height: 120, scale: 1, opacity: 1, rotation: 0, zIndex: 15, visible: true, locked: false, fitMode: 'contain' },
  },
};

export const DEFAULT_CONFIG: EngineConfig = {
  version: '1.0.0',
  appDataPath: '',
  ndiStreamName: 'BackgroundEngine-PGM',
  ndiFps: 60,
  canvasWidth: 1920,
  canvasHeight: 1080,
  currentPosition: 'P1',
  autoMoveEnabled: true,
  autoMoveLoop: true,
  targets: {
    selectedGameId: '',
    selectedGameUrl: '',
    lastKnownGoodGameUrl: '',
    selectedChatId: '',
    selectedChatUrl: '',
    lastKnownGoodChatUrl: '',
  },
  configuredSources: [],
  positions: {
    P1: DEFAULT_P1,
    P2: DEFAULT_P2,
    P3: DEFAULT_P3,
  },
};
