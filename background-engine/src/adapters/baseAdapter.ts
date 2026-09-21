import { EventEmitter } from 'events';
import {
  SourceAdapterConfig,
  SourceHealth,
  SourceStatus,
  SourceType,
} from '../main/sourceTypes';

export abstract class BaseSourceAdapter extends EventEmitter {
  public readonly config: SourceAdapterConfig;
  protected status: SourceStatus = 'NO_SOURCE';
  protected health: SourceHealth = {
    status: 'NO_SOURCE',
    latencyMs: 0,
    fps: 0,
    lastDataTimestamp: 0,
    errorCount: 0,
  };

  constructor(config: SourceAdapterConfig) {
    super();
    this.config = config;
  }

  public getId(): string {
    return this.config.id;
  }

  public getType(): SourceType {
    return this.config.type;
  }

  public getStatus(): SourceStatus {
    return this.status;
  }

  public getHealth(): SourceHealth {
    return { ...this.health };
  }

  protected setStatus(status: SourceStatus, lastError?: string): void {
    const oldStatus = this.status;
    this.status = status;
    this.health.status = status;
    if (lastError) {
      this.health.lastError = lastError;
      this.health.errorCount++;
    }
    if (oldStatus !== status) {
      this.emit('status-changed', { id: this.config.id, status, oldStatus, lastError });
    }
    this.emit('health', this.getHealth());
  }

  protected updateHeartbeat(latencyMs: number = 0, fps: number = 0): void {
    this.health.lastDataTimestamp = Date.now();
    this.health.latencyMs = latencyMs;
    if (fps > 0) {
      this.health.fps = fps;
    }
    this.emit('health', this.getHealth());
  }

  public abstract connect(): Promise<void>;
  public abstract disconnect(): Promise<void>;
  public abstract reconnect(): Promise<void>;
  public abstract getCapabilities(): string[];
  public abstract getOutput(): any;
}
