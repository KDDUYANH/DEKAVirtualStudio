export type LayerType = 'image' | 'video' | 'browser' | 'game' | 'chat' | 'alert' | 'timer' | 'logo' | 'custom';

export interface LayerTransform {
  x: number; // percentage (0..100) or pixels
  y: number;
  width: number;
  height: number;
  scale: number;
  crop?: {
    top: number;
    right: number;
    bottom: number;
    left: number;
  };
}

export interface LayerStyle {
  opacity: number;
  blendMode: 'normal' | 'multiply' | 'screen' | 'overlay' | 'lighten';
  filter?: string;
  borderRadius?: number;
}

export interface LayerSource {
  url?: string;
  content?: string | Record<string, any>;
  refreshInterval?: number; // ms, 0 = no auto refresh
  fallbackUrl?: string; // offline fallback image
}

export interface LayerState {
  status: 'healthy' | 'warning' | 'error';
  lastPing?: number;
  lastReload?: number;
}

export interface Layer {
  id: string;
  name: string;
  type: LayerType;
  zIndex: number;
  visible: boolean;
  locked: boolean;
  transform: LayerTransform;
  style: LayerStyle;
  source: LayerSource;
  state: LayerState;
}

export interface Scene {
  tableId: string;
  mode: 'full' | 'transparent';
  resolution: {
    width: number;
    height: number;
  };
  fps: number;
  layers: Layer[];
  lockedProduction: boolean;
  publishedAt: number;
  version: number;
}

export interface DeviceSession {
  deviceId: string;
  deviceName: string;
  tableId: string;
  registeredAt: number;
  lastActive: number;
  persistentToken: string;
  currentAccessToken: string;
  status: 'online' | 'degraded' | 'offline';
}

export interface TableTelemetry {
  tableId: string;
  deviceId?: string;
  fps: number;
  droppedFrames: number;
  memoryUsageMb?: number;
  networkStatus: 'online' | 'degraded' | 'offline';
  activeLayersCount: number;
  layerStatuses: Record<string, 'healthy' | 'warning' | 'error'>;
  lastHeartbeat: number;
  uptimeSeconds: number;
}

export type WSClientType = 'output' | 'control';

export interface WSMessage {
  type: 
    | 'auth:handshake' 
    | 'auth:ack' 
    | 'auth:error'
    | 'state:sync' 
    | 'state:update_layer' 
    | 'state:add_layer'
    | 'state:remove_layer'
    | 'state:reorder_layers'
    | 'state:publish' 
    | 'state:lock_toggle'
    | 'action:trigger_alert' 
    | 'action:clear_alert' 
    | 'action:reload_layer'
    | 'telemetry:heartbeat' 
    | 'telemetry:report';
  tableId: string;
  payload?: any;
  timestamp: number;
}
