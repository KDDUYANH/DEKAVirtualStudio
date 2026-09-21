import WebSocket from 'ws';
import { BaseSourceAdapter } from './baseAdapter';
import {
  NormalizedChatMessage,
  NormalizedGameState,
  SourceAdapterConfig,
} from '../main/sourceTypes';

export class WebSocketSourceAdapter extends BaseSourceAdapter {
  private ws: WebSocket | null = null;
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private reconnectAttempts = 0;
  private isIntentionallyClosed = false;
  private pingInterval: NodeJS.Timeout | null = null;
  private latestGameState: NormalizedGameState | null = null;
  private latestChatMessage: NormalizedChatMessage | null = null;

  constructor(config: SourceAdapterConfig) {
    super(config);
  }

  public getCapabilities(): string[] {
    return ['WEBSOCKET_STREAM', 'STRUCTURED_DATA', 'GAME_STATE', 'CHAT_MESSAGES'];
  }

  public async connect(): Promise<void> {
    if (!this.config.wsEndpoint) {
      this.setStatus('OFFLINE', 'No WebSocket endpoint specified');
      return;
    }

    this.isIntentionallyClosed = false;
    this.setStatus('CONNECTING');

    try {
      this.ws = new WebSocket(this.config.wsEndpoint, {
        headers: this.config.customHeaders || {},
        handshakeTimeout: 5000,
      });

      this.ws.on('open', () => {
        this.reconnectAttempts = 0;
        this.setStatus('ONLINE');
        this.startHeartbeat();
      });

      this.ws.on('message', (data: WebSocket.Data) => {
        this.handleMessage(data);
      });

      this.ws.on('error', (err: Error) => {
        this.setStatus('DEGRADED', err.message);
      });

      this.ws.on('close', (code: number, reason: string) => {
        this.stopHeartbeat();
        if (!this.isIntentionallyClosed) {
          this.setStatus('OFFLINE', `Closed: ${code} ${reason.toString()}`);
          if (this.config.autoReconnect) {
            this.scheduleReconnect();
          }
        }
      });
    } catch (err: any) {
      this.setStatus('OFFLINE', err.message || 'Connection failed');
      throw err;
    }
  }

  private startHeartbeat(): void {
    if (this.pingInterval) clearInterval(this.pingInterval);
    this.pingInterval = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        const start = Date.now();
        this.ws.ping();
        this.updateHeartbeat(Date.now() - start);
      }
    }, 5000);
  }

  private stopHeartbeat(): void {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.config.maxReconnectAttempts) {
      this.setStatus('OFFLINE', 'Max reconnect attempts exceeded');
      return;
    }

    this.reconnectAttempts++;
    this.setStatus('RECONNECTING');

    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 15000);
    this.reconnectTimeout = setTimeout(() => {
      this.connect().catch(() => {});
    }, delay);
  }

  private handleMessage(data: WebSocket.Data): void {
    try {
      const text = data.toString();
      const parsed = JSON.parse(text);
      this.updateHeartbeat(10);

      // Analyze whether it's Game State or Chat Message
      if (this.isGameStateMessage(parsed)) {
        const normalized = this.normalizeGameState(parsed);
        this.latestGameState = normalized;
        this.emit('game-state', normalized);
      } else if (this.isChatMessage(parsed)) {
        const normalized = this.normalizeChatMessage(parsed);
        this.latestChatMessage = normalized;
        this.emit('chat-message', normalized);
      } else {
        // Generic normalized event
        this.emit('data', {
          sourceId: this.getId(),
          raw: parsed,
          timestamp: Date.now(),
        });
      }
    } catch {
      // Non-JSON binary or raw text frame
      this.updateHeartbeat(5);
      this.emit('data', {
        sourceId: this.getId(),
        raw: data.toString(),
        timestamp: Date.now(),
      });
    }
  }

  private isGameStateMessage(obj: any): boolean {
    if (!obj || typeof obj !== 'object') return false;
    const keys = Object.keys(obj).map((k) => k.toLowerCase());
    return (
      keys.some((k) => k.includes('round') || k.includes('session') || k.includes('gameid')) ||
      keys.some((k) => k.includes('countdown') || k.includes('remain') || k.includes('timer')) ||
      keys.some((k) => k.includes('result') || k.includes('dice') || k.includes('card') || k.includes('win'))
    );
  }

  private isChatMessage(obj: any): boolean {
    if (!obj || typeof obj !== 'object') return false;
    const keys = Object.keys(obj).map((k) => k.toLowerCase());
    return (
      (keys.some((k) => k.includes('user') || k.includes('author') || k.includes('sender') || k.includes('name')) &&
        keys.some((k) => k.includes('msg') || k.includes('message') || k.includes('text') || k.includes('content'))) ||
      obj.cmd === 'chat' ||
      obj.type === 'chat'
    );
  }

  private normalizeGameState(obj: any): NormalizedGameState {
    let roundId: string | undefined;
    let countdownSeconds: number | undefined;
    let status: NormalizedGameState['status'] = 'WAITING';

    for (const [k, v] of Object.entries(obj)) {
      const lk = k.toLowerCase();
      if (lk.includes('round') || lk.includes('session') || lk.includes('gameid')) {
        roundId = String(v);
      } else if (lk.includes('countdown') || lk.includes('remain') || lk.includes('time')) {
        const parsedNum = Number(v);
        if (!isNaN(parsedNum)) countdownSeconds = parsedNum;
      } else if (lk.includes('status') || lk.includes('state')) {
        const valStr = String(v).toUpperCase();
        if (valStr.includes('BET') || valStr === '1') status = 'BETTING';
        else if (valStr.includes('RESULT') || valStr.includes('END') || valStr === '2') status = 'RESULT';
        else if (valStr.includes('CLOSE') || valStr === '3') status = 'CLOSED';
      }
    }

    return {
      status,
      roundId,
      countdownSeconds,
      result: {
        raw: obj,
      },
      statistics: obj,
      timestamp: Date.now(),
    };
  }

  private normalizeChatMessage(obj: any): NormalizedChatMessage {
    let username = 'User';
    let message = '';
    let id = String(Date.now());

    for (const [k, v] of Object.entries(obj)) {
      const lk = k.toLowerCase();
      if (lk.includes('user') || lk.includes('author') || lk.includes('sender') || lk.includes('name')) {
        username = String(v);
      } else if (lk.includes('msg') || lk.includes('message') || lk.includes('text') || lk.includes('content')) {
        message = String(v);
      } else if (lk === 'id' || lk.includes('msgid')) {
        id = String(v);
      }
    }

    return {
      id,
      username,
      message,
      timestamp: Date.now(),
      type: 'USER',
    };
  }

  public async disconnect(): Promise<void> {
    this.isIntentionallyClosed = true;
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.removeAllListeners();
      this.ws.on('error', () => {}); // Retain no-op handler so abort during CONNECTING doesn't throw uncaughtException
      try {
        this.ws.close();
      } catch {}
      this.ws = null;
    }
    this.setStatus('OFFLINE');
  }

  public async reconnect(): Promise<void> {
    await this.disconnect();
    this.reconnectAttempts = 0;
    await this.connect();
  }

  public getOutput(): any {
    return {
      type: 'WEBSOCKET_DATA',
      sourceId: this.getId(),
      status: this.status,
      health: this.getHealth(),
      latestGameState: this.latestGameState,
      latestChatMessage: this.latestChatMessage,
    };
  }
}
