import fs from 'fs';
import path from 'path';
import { CONFIG } from '../config.js';
import { Scene, Layer } from '../types.js';
import { createDefaultScene } from './defaultPresets.js';

export class SceneManager {
  private scenes: Map<string, Scene> = new Map();
  private storageFile: string;

  constructor() {
    this.storageFile = path.join(CONFIG.STORAGE_DIR, 'scenes.json');
    this.init();
  }

  private init(): void {
    try {
      if (!fs.existsSync(CONFIG.STORAGE_DIR)) {
        fs.mkdirSync(CONFIG.STORAGE_DIR, { recursive: true });
      }

      if (fs.existsSync(this.storageFile)) {
        const raw = fs.readFileSync(this.storageFile, 'utf-8');
        const data: Record<string, Scene> = JSON.parse(raw);
        Object.entries(data).forEach(([tableId, scene]) => {
          this.scenes.set(tableId, scene);
        });
      }
    } catch (err) {
      console.error('[SceneManager] Failed to read scenes from disk:', err);
    }

    // Ensure all default tables exist
    CONFIG.DEFAULT_TABLES.forEach((tableId) => {
      if (!this.scenes.has(tableId)) {
        this.scenes.set(tableId, createDefaultScene(tableId));
      }
    });

    this.save();
  }

  public save(): void {
    try {
      if (!fs.existsSync(CONFIG.STORAGE_DIR)) {
        fs.mkdirSync(CONFIG.STORAGE_DIR, { recursive: true });
      }
      const data: Record<string, Scene> = {};
      this.scenes.forEach((scene, id) => {
        data[id] = scene;
      });
      fs.writeFileSync(this.storageFile, JSON.stringify(data, null, 2), 'utf-8');
    } catch (err) {
      console.error('[SceneManager] Failed to write scenes to disk:', err);
    }
  }

  public getScene(tableId: string): Scene {
    if (!this.scenes.has(tableId)) {
      this.scenes.set(tableId, createDefaultScene(tableId));
      this.save();
    }
    return this.scenes.get(tableId)!;
  }

  public getAllTables(): string[] {
    return Array.from(this.scenes.keys());
  }

  public updateLayer(tableId: string, layerId: string, partial: Partial<Layer>): Scene {
    const scene = this.getScene(tableId);
    if (scene.lockedProduction && !partial.state) {
      throw new Error(`Table ${tableId} is locked in Production Mode. Unlock to modify layers.`);
    }

    const index = scene.layers.findIndex((l) => l.id === layerId);
    if (index === -1) {
      throw new Error(`Layer ${layerId} not found in ${tableId}`);
    }

    const current = scene.layers[index];
    scene.layers[index] = {
      ...current,
      ...partial,
      transform: { ...current.transform, ...partial.transform },
      style: { ...current.style, ...partial.style },
      source: { ...current.source, ...partial.source },
      state: { ...current.state, ...partial.state },
    };

    scene.version += 1;
    this.save();
    return scene;
  }

  public setProductionLock(tableId: string, locked: boolean): Scene {
    const scene = this.getScene(tableId);
    scene.lockedProduction = locked;
    scene.version += 1;
    this.save();
    return scene;
  }

  public setMode(tableId: string, mode: 'full' | 'transparent'): Scene {
    const scene = this.getScene(tableId);
    if (scene.lockedProduction) {
      throw new Error(`Table ${tableId} is locked in Production Mode.`);
    }
    scene.mode = mode;
    scene.version += 1;
    this.save();
    return scene;
  }

  public triggerAlert(tableId: string, payload: { title: string; message: string; severity?: 'info' | 'warning' | 'critical' }): Scene {
    const scene = this.getScene(tableId);
    const alertLayer = scene.layers.find((l) => l.type === 'alert');
    if (alertLayer) {
      alertLayer.visible = true;
      alertLayer.source.content = {
        title: payload.title,
        message: payload.message,
        severity: payload.severity || 'warning',
      };
      scene.version += 1;
      this.save();
    }
    return scene;
  }

  public clearAlert(tableId: string): Scene {
    const scene = this.getScene(tableId);
    const alertLayer = scene.layers.find((l) => l.type === 'alert');
    if (alertLayer) {
      alertLayer.visible = false;
      scene.version += 1;
      this.save();
    }
    return scene;
  }

  public reorderLayers(tableId: string, orderedLayerIds: string[]): Scene {
    const scene = this.getScene(tableId);
    if (scene.lockedProduction) {
      throw new Error(`Table ${tableId} is locked in Production Mode.`);
    }

    const layerMap = new Map(scene.layers.map((l) => [l.id, l]));
    const newLayers: Layer[] = [];

    orderedLayerIds.forEach((id, idx) => {
      const layer = layerMap.get(id);
      if (layer) {
        layer.zIndex = idx + 1;
        newLayers.push(layer);
        layerMap.delete(id);
      }
    });

    // Add any remaining layers
    layerMap.forEach((layer) => {
      layer.zIndex = newLayers.length + 1;
      newLayers.push(layer);
    });

    scene.layers = newLayers;
    scene.version += 1;
    this.save();
    return scene;
  }

  public resetTableToDefault(tableId: string): Scene {
    const fresh = createDefaultScene(tableId);
    this.scenes.set(tableId, fresh);
    this.save();
    return fresh;
  }
}
