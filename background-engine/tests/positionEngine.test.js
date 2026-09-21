import test from 'node:test';
import assert from 'node:assert/strict';

class PositionEngine {
  constructor() {
    this.activePosition = 'P1';
    this.presets = {
      P1: { id: 'P1', durationSeconds: 30, layers: { game: { x: 50, y: 120, width: 1280, height: 720 } } },
      P2: { id: 'P2', durationSeconds: 20, layers: { game: { x: 50, y: 120, width: 1100, height: 620 } } },
      P3: { id: 'P3', durationSeconds: 30, layers: { game: { x: 50, y: 120, width: 1360, height: 765 } } },
    };
    this.reloadedSourcesCount = 0;
  }

  setPosition(posId) {
    if (!this.presets[posId]) return;
    this.activePosition = posId;
    // CRITICAL: Changing position must NOT reload sources
  }

  savePreset(posId, preset) {
    this.presets[posId] = JSON.parse(JSON.stringify(preset));
  }
}

test('PositionEngine - Default active position is P1', () => {
  const engine = new PositionEngine();
  assert.equal(engine.activePosition, 'P1');
});

test('PositionEngine - Switching between P1, P2, P3 changes layout geometry only', () => {
  const engine = new PositionEngine();

  engine.setPosition('P2');
  assert.equal(engine.activePosition, 'P2');
  assert.equal(engine.presets[engine.activePosition].layers.game.width, 1100);
  assert.equal(engine.reloadedSourcesCount, 0, 'Source must never be reloaded on position change');

  engine.setPosition('P3');
  assert.equal(engine.activePosition, 'P3');
  assert.equal(engine.presets[engine.activePosition].layers.game.width, 1360);
  assert.equal(engine.reloadedSourcesCount, 0);
});

test('PositionEngine - Save P1/P2/P3 updates preset geometry', () => {
  const engine = new PositionEngine();
  const modified = { id: 'P2', durationSeconds: 25, layers: { game: { x: 100, y: 150, width: 1000, height: 600 } } };
  engine.savePreset('P2', modified);

  assert.equal(engine.presets.P2.durationSeconds, 25);
  assert.equal(engine.presets.P2.layers.game.x, 100);
});
