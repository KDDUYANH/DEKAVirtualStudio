/**
 * UNIVERSAL SOURCE DISCOVERY & ADAPTER DATA MODELS
 * Standard interfaces for real-time video, structured game state, and chat streams.
 * Zero-mock architecture: No fake rounds, demo chat, or hardcoded website logic.
 */

export type SourceType =
  | 'BROWSER'
  | 'VIDEO'
  | 'IFRAME'
  | 'CANVAS'
  | 'WEBGL'
  | 'WEBSOCKET'
  | 'SSE'
  | 'REST'
  | 'DOM'
  | 'SCREEN_CAPTURE'
  | 'IMAGE'
  | 'LOCAL_MEDIA';

export type SourceStatus =
  | 'NO_SOURCE'
  | 'DISCOVERING'
  | 'AUTH_REQUIRED'
  | 'CONNECTING'
  | 'ONLINE'
  | 'DEGRADED'
  | 'RECONNECTING'
  | 'OFFLINE';

export type SourceClassification =
  | 'GAME_VIDEO'
  | 'GAME_UI'
  | 'GAME_STATE'
  | 'CHAT'
  | 'COUNTDOWN'
  | 'RESULT'
  | 'HISTORY'
  | 'BRANDING'
  | 'BACKGROUND'
  | 'UNRELATED'
  | 'ANALYTICS'
  | 'ADVERTISING'
  | 'AUTHENTICATION'
  | 'PAYMENT';

export type IntegrationRecommendation =
  | 'KEEP_BROWSER'
  | 'EXTRACT_DATA'
  | 'RECREATE_NATIVE'
  | 'IGNORE';

export interface SourceCandidate {
  id: string;
  name: string;
  type: SourceType;
  classification: SourceClassification;
  recommendation: IntegrationRecommendation;
  reason: string;
  confidence: number;
  dependencies?: string[];
  risks?: string[];
  details: {
    url?: string;
    selector?: string;
    protocol?: string;
    width?: number;
    height?: number;
    fps?: number;
    messageRateHz?: number;
    detectedFields?: string[];
  };
}

export interface SourceHealth {
  status: SourceStatus;
  latencyMs: number;
  fps: number;
  lastDataTimestamp: number;
  errorCount: number;
  lastError?: string;
  details?: Record<string, any>;
}

export interface NormalizedGameState {
  status: 'WAITING' | 'BETTING' | 'CLOSED' | 'RESULT' | 'PAUSED' | 'UNKNOWN';
  roundId?: string;
  countdownSeconds?: number;
  result?: {
    winningOutcome?: string;
    dice?: number[];
    cards?: string[];
    raw?: any;
  };
  statistics?: Record<string, any>;
  timestamp: number;
}

export interface NormalizedChatMessage {
  id: string;
  username: string;
  message: string;
  timestamp: number;
  type: 'USER' | 'MOD' | 'SYSTEM' | 'VIP';
  vipLevel?: number;
  avatarUrl?: string;
}

export interface SourceAdapterConfig {
  id: string;
  name: string;
  type: SourceType;
  targetUrl: string;
  selector?: string;
  wsEndpoint?: string;
  autoReconnect: boolean;
  maxReconnectAttempts: number;
  customHeaders?: Record<string, string>;
  boundLayerKey?: 'game' | 'chat' | 'warning' | 'logo' | 'payment';
}
