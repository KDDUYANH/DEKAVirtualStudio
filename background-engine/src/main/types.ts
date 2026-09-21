/**
 * DEKA BACKGROUND ENGINE — CORE TYPE DEFINITIONS
 * Authoritative system schemas for Fail-Closed Safety Gate, 3-Position Presets,
 * Auto Move Timeline, and NDI High Bandwidth Output Pipeline.
 */

export type SafetyGateState =
  | 'PROGRAM_SAFE'
  | 'PROGRAM_READY'
  | 'PROGRAM_DEGRADED'
  | 'PROGRAM_AUTH_REQUIRED';

export type GameSourceState =
  | 'STARTING'
  | 'LOADING'
  | 'READY'
  | 'LIVE'
  | 'BUFFERING'
  | 'DISCONNECTED'
  | 'ROUTE_LOST'
  | 'RECONNECTING'
  | 'AUTH_REQUIRED'
  | 'FAILED';

export type ChatSourceState =
  | 'STARTING'
  | 'LOADING'
  | 'READY'
  | 'CONNECTED'
  | 'DISCONNECTED'
  | 'ROUTE_LOST'
  | 'RECONNECTING'
  | 'AUTH_REQUIRED'
  | 'FAILED';

export type PositionId = 'P1' | 'P2' | 'P3';

export type AutoMoveState = 'STOPPED' | 'RUNNING' | 'PAUSED';

export type OutputState = 'CONNECTED' | 'DISCONNECTED' | 'RECONNECTING' | 'FAILED';

export interface LayerGeometry {
  x: number;          // Position X in px (based on 1920 canvas)
  y: number;          // Position Y in px (based on 1080 canvas)
  width: number;      // Width in px
  height: number;     // Height in px
  scale: number;      // Scale multiplier (1.0 = 100%)
  crop?: {
    top: number;
    right: number;
    bottom: number;
    left: number;
  };
  opacity: number;    // 0.0 - 1.0
  rotation: number;   // In degrees
  zIndex: number;     // Render order
  visible: boolean;
  locked: boolean;
  fitMode: 'cover' | 'contain' | 'fill' | 'none';
}

export interface PositionPreset {
  id: PositionId;
  name: string;
  durationSeconds: number; // Configurable duration in Auto Move (e.g. 30s, 20s)
  layers: {
    game: LayerGeometry;
    chat: LayerGeometry;
    warning: LayerGeometry;
    logo: LayerGeometry;
    payment: LayerGeometry;
    timer: LayerGeometry;
    background: LayerGeometry;
  };
}

export interface TargetConfig {
  selectedGameId: string;
  selectedGameUrl: string;
  lastKnownGoodGameUrl: string;
  selectedChatId: string;
  selectedChatUrl: string;
  lastKnownGoodChatUrl: string;
}

export interface EngineConfig {
  version: string;
  appDataPath: string;
  ndiStreamName: string;
  ndiFps: number;
  canvasWidth: number;
  canvasHeight: number;
  currentPosition: PositionId;
  autoMoveEnabled: boolean;
  autoMoveLoop: boolean;
  targets: TargetConfig;
  positions: {
    P1: PositionPreset;
    P2: PositionPreset;
    P3: PositionPreset;
  };
}

export interface EngineTelemetry {
  fps: number;
  frameTimeMs: number;
  droppedFrames: number;
  compositorLatencyMs: number;
  cpuPercent: number;
  memoryMb: number;
  uptimeSeconds: number;
  safetyState: SafetyGateState;
  gameState: GameSourceState;
  chatState: ChatSourceState;
  outputState: OutputState;
  ndiReceiversCount: number;
  activePosition: PositionId;
  autoMoveRemainingSeconds: number;
  nextPosition: PositionId;
}

export interface ChatMessage {
  id: string;
  user: string;
  vip: number;
  text: string;
  timestamp: number;
  mod?: boolean;
}
