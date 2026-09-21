import { EventEmitter } from 'events';
import { BaseSourceAdapter } from './baseAdapter';
import { BrowserSourceAdapter } from './browserSourceAdapter';
import { WebSocketSourceAdapter } from './websocketSourceAdapter';
import {
  NormalizedChatMessage,
  NormalizedGameState,
  SourceAdapterConfig,
  SourceHealth,
} from '../main/sourceTypes';

export class AdapterManager extends EventEmitter {
  private adapters: Map<string, BaseSourceAdapter> = new Map();

  public async registerAdapter(config: SourceAdapterConfig): Promise<BaseSourceAdapter> {
    if (this.adapters.has(config.id)) {
      await this.removeAdapter(config.id);
    }

    let adapter: BaseSourceAdapter;
    if (config.type === 'WEBSOCKET') {
      adapter = new WebSocketSourceAdapter(config);
    } else {
      // Default to Browser/Video isolated render
      adapter = new BrowserSourceAdapter(config);
    }

    // Bind event propagation
    adapter.on('status-changed', (event) => {
      this.emit('adapter-status-changed', event);
    });

    adapter.on('health', (health: SourceHealth) => {
      this.emit('adapter-health', { id: config.id, health });
    });

    adapter.on('frame', (frame) => {
      this.emit('adapter-frame', frame);
    });

    adapter.on('game-state', (state: NormalizedGameState) => {
      this.emit('adapter-game-state', { sourceId: config.id, state });
    });

    adapter.on('chat-message', (msg: NormalizedChatMessage) => {
      this.emit('adapter-chat-message', { sourceId: config.id, msg });
    });

    this.adapters.set(config.id, adapter);

    try {
      await adapter.connect();
    } catch (err) {
      console.warn(`[AdapterManager] Adapter ${config.id} initial connect error:`, err);
    }

    return adapter;
  }

  public async removeAdapter(id: string): Promise<boolean> {
    const adapter = this.adapters.get(id);
    if (!adapter) return false;

    try {
      await adapter.disconnect();
      adapter.removeAllListeners();
    } catch (e) {
      console.error(`[AdapterManager] Error disconnecting adapter ${id}:`, e);
    }

    this.adapters.delete(id);
    this.emit('adapter-removed', id);
    return true;
  }

  public getAdapter(id: string): BaseSourceAdapter | undefined {
    return this.adapters.get(id);
  }

  public getAllAdapters(): BaseSourceAdapter[] {
    return Array.from(this.adapters.values());
  }

  public getHealthSummary(): Record<string, SourceHealth> {
    const summary: Record<string, SourceHealth> = {};
    for (const [id, adapter] of this.adapters.entries()) {
      summary[id] = adapter.getHealth();
    }
    return summary;
  }

  public async shutdown(): Promise<void> {
    const promises = Array.from(this.adapters.keys()).map((id) => this.removeAdapter(id));
    await Promise.allSettled(promises);
  }
}
