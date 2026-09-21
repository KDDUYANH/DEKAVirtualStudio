import { EventEmitter } from 'events';
import { PositionId, PositionPreset, LayerGeometry } from '../main/types.js';
import { DEFAULT_P1, DEFAULT_P2, DEFAULT_P3 } from '../main/defaultPresets.js';

export class PositionEngine extends EventEmitter {
  private activePosition: PositionId = 'P1';
  private presets: Record<PositionId, PositionPreset>;

  constructor(initialPresets?: { P1?: PositionPreset; P2?: PositionPreset; P3?: PositionPreset }, initialPos: PositionId = 'P1') {
    super();
    this.presets = {
      P1: initialPresets?.P1 || JSON.parse(JSON.stringify(DEFAULT_P1)),
      P2: initialPresets?.P2 || JSON.parse(JSON.stringify(DEFAULT_P2)),
      P3: initialPresets?.P3 || JSON.parse(JSON.stringify(DEFAULT_P3)),
    };
    this.activePosition = initialPos;
  }

  public getActivePosition(): PositionId {
    return this.activePosition;
  }

  public getActivePreset(): PositionPreset {
    return JSON.parse(JSON.stringify(this.presets[this.activePosition]));
  }

  public getPreset(id: PositionId): PositionPreset {
    return JSON.parse(JSON.stringify(this.presets[id]));
  }

  public getAllPresets(): Record<PositionId, PositionPreset> {
    return JSON.parse(JSON.stringify(this.presets));
  }

  public setPosition(id: PositionId): void {
    if (!this.presets[id]) return;
    const prev = this.activePosition;
    this.activePosition = id;

    console.log(`[PositionEngine] Switched Position: ${prev} -> ${id}`);
    this.emit('position-changed', {
      previous: prev,
      current: id,
      preset: this.getActivePreset(),
    });
  }

  public updateLayerGeometry(posId: PositionId, layerKey: keyof PositionPreset['layers'], geometry: Partial<LayerGeometry>): void {
    if (!this.presets[posId] || !this.presets[posId].layers[layerKey]) return;
    
    this.presets[posId].layers[layerKey] = {
      ...this.presets[posId].layers[layerKey],
      ...geometry,
    };

    this.emit('preset-updated', {
      posId,
      preset: this.getPreset(posId),
    });

    if (posId === this.activePosition) {
      this.emit('active-geometry-updated', {
        layerKey,
        geometry: this.presets[posId].layers[layerKey],
      });
    }
  }

  public savePreset(posId: PositionId, preset: PositionPreset): void {
    this.presets[posId] = JSON.parse(JSON.stringify(preset));
    console.log(`[PositionEngine] Saved preset for ${posId}`);
    this.emit('preset-saved', { posId, preset: this.getPreset(posId) });

    if (posId === this.activePosition) {
      this.emit('position-changed', {
        previous: posId,
        current: posId,
        preset: this.getActivePreset(),
      });
    }
  }
}
