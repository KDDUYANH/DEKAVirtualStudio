import test from 'node:test';
import assert from 'node:assert/strict';

// Test Safety Gate state transitions
class SafetyGate {
  constructor() {
    this.currentState = 'PROGRAM_SAFE';
    this.inputs = {
      isAuthenticated: false,
      isGameVerified: false,
      isGameHealthy: false,
      isChatVerified: false,
      isChatHealthy: false,
    };
  }

  getState() {
    return this.currentState;
  }

  updateInputs(partial) {
    this.inputs = { ...this.inputs, ...partial };
    this.currentState = this.computeState();
    return this.currentState;
  }

  computeState() {
    if (!this.inputs.isAuthenticated) {
      return 'PROGRAM_AUTH_REQUIRED';
    }

    const gameOk = this.inputs.isGameVerified && this.inputs.isGameHealthy;
    const chatOk = this.inputs.isChatVerified && this.inputs.isChatHealthy;

    if (gameOk && chatOk) {
      return 'PROGRAM_READY';
    }

    if (gameOk || chatOk) {
      return 'PROGRAM_DEGRADED';
    }

    return 'PROGRAM_SAFE';
  }

  isDynamicLayerAllowed(layerType) {
    if (this.currentState === 'PROGRAM_AUTH_REQUIRED' || this.currentState === 'PROGRAM_SAFE') {
      return false;
    }
    if (layerType === 'game') {
      return this.inputs.isAuthenticated && this.inputs.isGameVerified && this.inputs.isGameHealthy;
    }
    if (layerType === 'chat') {
      return this.inputs.isAuthenticated && this.inputs.isChatVerified && this.inputs.isChatHealthy;
    }
    return false;
  }
}

test('SafetyGate - Default state must be PROGRAM_SAFE before evaluation', () => {
  const gate = new SafetyGate();
  assert.equal(gate.getState(), 'PROGRAM_SAFE');
});

test('SafetyGate - Unauthenticated fails-closed to PROGRAM_AUTH_REQUIRED', () => {
  const gate = new SafetyGate();
  const state = gate.updateInputs({ isAuthenticated: false });
  assert.equal(state, 'PROGRAM_AUTH_REQUIRED');
  assert.equal(gate.isDynamicLayerAllowed('game'), false);
  assert.equal(gate.isDynamicLayerAllowed('chat'), false);
});

test('SafetyGate - Authenticated but sources not ready stays PROGRAM_SAFE', () => {
  const gate = new SafetyGate();
  const state = gate.updateInputs({ isAuthenticated: true });
  assert.equal(state, 'PROGRAM_SAFE');
  assert.equal(gate.isDynamicLayerAllowed('game'), false);
  assert.equal(gate.isDynamicLayerAllowed('chat'), false);
});

test('SafetyGate - Auth valid + Game valid + Chat valid transitions to PROGRAM_READY', () => {
  const gate = new SafetyGate();
  gate.updateInputs({
    isAuthenticated: true,
    isGameVerified: true,
    isGameHealthy: true,
    isChatVerified: true,
    isChatHealthy: true,
  });
  assert.equal(gate.getState(), 'PROGRAM_READY');
  assert.equal(gate.isDynamicLayerAllowed('game'), true);
  assert.equal(gate.isDynamicLayerAllowed('chat'), true);
});

test('SafetyGate - Game route lost drops to PROGRAM_DEGRADED while Chat survives', () => {
  const gate = new SafetyGate();
  gate.updateInputs({
    isAuthenticated: true,
    isGameVerified: true,
    isGameHealthy: true,
    isChatVerified: true,
    isChatHealthy: true,
  });

  // Game fails
  gate.updateInputs({ isGameHealthy: false });
  assert.equal(gate.getState(), 'PROGRAM_DEGRADED');
  assert.equal(gate.isDynamicLayerAllowed('game'), false);
  assert.equal(gate.isDynamicLayerAllowed('chat'), true); // Chat continues!
});

test('SafetyGate - Immediate fail-closed on auth logout', () => {
  const gate = new SafetyGate();
  gate.updateInputs({
    isAuthenticated: true,
    isGameVerified: true,
    isGameHealthy: true,
    isChatVerified: true,
    isChatHealthy: true,
  });
  assert.equal(gate.getState(), 'PROGRAM_READY');

  // Logout
  gate.updateInputs({ isAuthenticated: false });
  assert.equal(gate.getState(), 'PROGRAM_AUTH_REQUIRED');
  assert.equal(gate.isDynamicLayerAllowed('game'), false);
  assert.equal(gate.isDynamicLayerAllowed('chat'), false);
});
