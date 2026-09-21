import test from 'node:test';
import assert from 'node:assert';
import { SceneManager } from '../src/state/sceneManager.js';

test('SceneManager - Multi-Layer Compositing & State Isolation', async (t) => {
  const manager = new SceneManager();
  const tableId = 'test-table-99';

  await t.test('1. Should initialize with default 7-layer broadcast scene', () => {
    const scene = manager.getScene(tableId);
    assert.strictEqual(scene.tableId, tableId);
    assert.strictEqual(scene.layers.length, 7);
    assert.strictEqual(scene.lockedProduction, false);

    // Verify presence of core layers
    const types = scene.layers.map(l => l.type);
    assert.ok(types.includes('image'), 'Must have base background');
    assert.ok(types.includes('game'), 'Must have game layer');
    assert.ok(types.includes('chat'), 'Must have chat layer');
    assert.ok(types.includes('logo'), 'Must have logo layer');
    assert.ok(types.includes('timer'), 'Must have timer layer');
    assert.ok(types.includes('alert'), 'Must have alert layer');
    assert.ok(types.includes('custom'), 'Must have custom ticker layer');
  });

  await t.test('2. Should update layer transform and style', () => {
    const scene = manager.getScene(tableId);
    const layer = scene.layers[0];
    const updated = manager.updateLayer(tableId, layer.id, {
      transform: { ...layer.transform, x: 12.5, y: 15.0 },
      style: { ...layer.style, opacity: 0.8 },
    });

    const target = updated.layers.find(l => l.id === layer.id);
    assert.strictEqual(target?.transform.x, 12.5);
    assert.strictEqual(target?.transform.y, 15.0);
    assert.strictEqual(target?.style.opacity, 0.8);
  });

  await t.test('3. Should reorder layers and update Z-Index', () => {
    const scene = manager.getScene(tableId);
    const ids = scene.layers.map(l => l.id).reverse();
    const reordered = manager.reorderLayers(tableId, ids);

    assert.strictEqual(reordered.layers[0].id, ids[0]);
    assert.strictEqual(reordered.layers[0].zIndex, 1);
  });

  await t.test('4. Locked Production Mode prevents accidental layer modifications', () => {
    manager.setProductionLock(tableId, true);
    const scene = manager.getScene(tableId);
    assert.strictEqual(scene.lockedProduction, true);

    assert.throws(() => {
      manager.updateLayer(tableId, scene.layers[0].id, { visible: false });
    }, /locked in Production Mode/);

    // Unlock
    manager.setProductionLock(tableId, false);
    const unlocked = manager.getScene(tableId);
    assert.strictEqual(unlocked.lockedProduction, false);
  });

  await t.test('5. Alert trigger and clear lifecycle', () => {
    const triggered = manager.triggerAlert(tableId, {
      title: 'EMERGENCY JACKPOT',
      message: 'Huge prize won on Table 99!',
      severity: 'warning',
    });

    const alertLayer = triggered.layers.find(l => l.type === 'alert');
    assert.strictEqual(alertLayer?.visible, true);
    assert.strictEqual((alertLayer?.source.content as any)?.title, 'EMERGENCY JACKPOT');

    const cleared = manager.clearAlert(tableId);
    const alertLayerCleared = cleared.layers.find(l => l.type === 'alert');
    assert.strictEqual(alertLayerCleared?.visible, false);
  });

  await t.test('6. Transparent mode toggle for vMix alpha channel overlay', () => {
    manager.setMode(tableId, 'transparent');
    assert.strictEqual(manager.getScene(tableId).mode, 'transparent');

    manager.setMode(tableId, 'full');
    assert.strictEqual(manager.getScene(tableId).mode, 'full');
  });
});
