import jwt from 'jsonwebtoken';
import { CONFIG } from '../config.js';
import { DeviceSession } from '../types.js';
import fs from 'fs';
import path from 'path';

export class DeviceAuthManager {
  private sessions: Map<string, DeviceSession> = new Map();
  private storageFile: string;

  constructor() {
    this.storageFile = path.join(CONFIG.STORAGE_DIR, 'sessions.json');
    this.loadSessions();
  }

  private loadSessions(): void {
    try {
      if (!fs.existsSync(CONFIG.STORAGE_DIR)) {
        fs.mkdirSync(CONFIG.STORAGE_DIR, { recursive: true });
      }
      if (fs.existsSync(this.storageFile)) {
        const raw = fs.readFileSync(this.storageFile, 'utf-8');
        const data = JSON.parse(raw);
        if (Array.isArray(data)) {
          data.forEach((s: DeviceSession) => this.sessions.set(s.deviceId, s));
        }
      }
    } catch (err) {
      console.error('[DeviceAuth] Failed to load sessions from disk:', err);
    }
  }

  public saveSessions(): void {
    try {
      if (!fs.existsSync(CONFIG.STORAGE_DIR)) {
        fs.mkdirSync(CONFIG.STORAGE_DIR, { recursive: true });
      }
      const data = Array.from(this.sessions.values());
      fs.writeFileSync(this.storageFile, JSON.stringify(data, null, 2), 'utf-8');
    } catch (err) {
      console.error('[DeviceAuth] Failed to save sessions to disk:', err);
    }
  }

  /**
   * Register a new or existing Studio Device (Mini PC, vMix Operator Station)
   */
  public registerDevice(deviceId: string, deviceName: string, tableId: string): { persistentToken: string; accessToken: string; session: DeviceSession } {
    const existing = this.sessions.get(deviceId);
    const now = Date.now();

    const persistentPayload = {
      deviceId,
      deviceName,
      tableId,
      type: 'persistent',
    };

    const persistentToken = jwt.sign(persistentPayload, CONFIG.JWT_SECRET, {
      expiresIn: CONFIG.JWT_PERSISTENT_EXPIRY as any,
    });

    const accessPayload = {
      deviceId,
      deviceName,
      tableId,
      type: 'access',
    };

    const accessToken = jwt.sign(accessPayload, CONFIG.JWT_SECRET, {
      expiresIn: CONFIG.JWT_ACCESS_EXPIRY as any,
    });

    const session: DeviceSession = {
      deviceId,
      deviceName,
      tableId,
      registeredAt: existing?.registeredAt || now,
      lastActive: now,
      persistentToken,
      currentAccessToken: accessToken,
      status: 'online',
    };

    this.sessions.set(deviceId, session);
    this.saveSessions();

    return { persistentToken, accessToken, session };
  }

  /**
   * Silent Refresh: Exchanges a valid persistentToken for a new short-lived accessToken
   */
  public refreshAccessToken(persistentToken: string): { accessToken: string; deviceId: string; tableId: string } | null {
    try {
      const decoded = jwt.verify(persistentToken, CONFIG.JWT_SECRET) as any;
      if (decoded.type !== 'persistent') {
        return null;
      }

      const session = this.sessions.get(decoded.deviceId);
      if (!session) {
        return null;
      }

      const accessPayload = {
        deviceId: session.deviceId,
        deviceName: session.deviceName,
        tableId: session.tableId,
        type: 'access',
      };

      const newAccessToken = jwt.sign(accessPayload, CONFIG.JWT_SECRET, {
        expiresIn: CONFIG.JWT_ACCESS_EXPIRY as any,
      });

      session.currentAccessToken = newAccessToken;
      session.lastActive = Date.now();
      session.status = 'online';
      this.sessions.set(session.deviceId, session);
      this.saveSessions();

      return {
        accessToken: newAccessToken,
        deviceId: session.deviceId,
        tableId: session.tableId,
      };
    } catch (err) {
      console.warn('[DeviceAuth] Refresh token failed verification:', err);
      return null;
    }
  }

  /**
   * Verify an access token (used by REST API or WebSocket handshake)
   */
  public verifyAccessToken(accessToken: string): { deviceId: string; tableId: string } | null {
    try {
      const decoded = jwt.verify(accessToken, CONFIG.JWT_SECRET) as any;
      return {
        deviceId: decoded.deviceId,
        tableId: decoded.tableId,
      };
    } catch {
      return null;
    }
  }

  public getSession(deviceId: string): DeviceSession | undefined {
    return this.sessions.get(deviceId);
  }

  public getAllSessions(): DeviceSession[] {
    return Array.from(this.sessions.values());
  }

  public touchSession(deviceId: string): void {
    const s = this.sessions.get(deviceId);
    if (s) {
      s.lastActive = Date.now();
      s.status = 'online';
    }
  }

  public revokeDevice(deviceId: string): boolean {
    const deleted = this.sessions.delete(deviceId);
    if (deleted) {
      this.saveSessions();
    }
    return deleted;
  }
}
