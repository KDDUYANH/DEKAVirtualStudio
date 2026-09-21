import { TableTelemetry } from '../types.js';
import { CONFIG } from '../config.js';

export class ServerWatchdog {
  private telemetryMap: Map<string, TableTelemetry> = new Map();

  public recordHeartbeat(data: Partial<TableTelemetry> & { tableId: string }): TableTelemetry {
    const now = Date.now();
    const existing = this.telemetryMap.get(data.tableId) || {
      tableId: data.tableId,
      fps: 60,
      droppedFrames: 0,
      networkStatus: 'online',
      activeLayersCount: 0,
      layerStatuses: {},
      lastHeartbeat: now,
      uptimeSeconds: 0,
    };

    const updated: TableTelemetry = {
      ...existing,
      ...data,
      lastHeartbeat: now,
      networkStatus: data.networkStatus || 'online',
    };

    this.telemetryMap.set(data.tableId, updated);
    return updated;
  }

  public getTelemetry(tableId: string): TableTelemetry {
    const now = Date.now();
    const entry = this.telemetryMap.get(tableId);

    if (!entry) {
      return {
        tableId,
        fps: 0,
        droppedFrames: 0,
        networkStatus: 'offline',
        activeLayersCount: 0,
        layerStatuses: {},
        lastHeartbeat: 0,
        uptimeSeconds: 0,
      };
    }

    // Check if heartbeat expired
    if (now - entry.lastHeartbeat > CONFIG.HEARTBEAT_TIMEOUT_MS) {
      entry.networkStatus = 'offline';
      entry.fps = 0;
    }

    return entry;
  }

  public getAllTelemetry(): TableTelemetry[] {
    return Array.from(this.telemetryMap.keys()).map((id) => this.getTelemetry(id));
  }
}
