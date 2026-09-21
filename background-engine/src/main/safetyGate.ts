import { EventEmitter } from 'events';
import { SafetyGateState } from './types.js';

export interface SafetyInputs {
  isAuthenticated: boolean;
  isGameVerified: boolean;
  isGameHealthy: boolean;
  isChatVerified: boolean;
  isChatHealthy: boolean;
}

export class SafetyGate extends EventEmitter {
  private currentState: SafetyGateState = 'PROGRAM_SAFE';
  private inputs: SafetyInputs = {
    isAuthenticated: false,
    isGameVerified: false,
    isGameHealthy: false,
    isChatVerified: false,
    isChatHealthy: false,
  };

  constructor() {
    super();
  }

  public getState(): SafetyGateState {
    return this.currentState;
  }

  public getInputs(): SafetyInputs {
    return { ...this.inputs };
  }

  public updateInputs(partial: Partial<SafetyInputs>): SafetyGateState {
    const prevInputs = { ...this.inputs };
    this.inputs = { ...this.inputs, ...partial };

    const newState = this.computeState();
    if (newState !== this.currentState) {
      const oldState = this.currentState;
      this.currentState = newState;
      console.log(`[SafetyGate] State Transition: ${oldState} -> ${newState}`);
      this.emit('state-changed', {
        previous: oldState,
        current: newState,
        inputs: { ...this.inputs },
      });
    }

    return this.currentState;
  }

  private computeState(): SafetyGateState {
    // 1. If auth is not valid, ALWAYS fail-closed to PROGRAM_AUTH_REQUIRED
    if (!this.inputs.isAuthenticated) {
      return 'PROGRAM_AUTH_REQUIRED';
    }

    const gameOk = this.inputs.isGameVerified && this.inputs.isGameHealthy;
    const chatOk = this.inputs.isChatVerified && this.inputs.isChatHealthy;

    // 2. Both dynamic sources verified and healthy -> PROGRAM_READY
    if (gameOk && chatOk) {
      return 'PROGRAM_READY';
    }

    // 3. At least one source is operating, but other is degraded/reconnecting -> PROGRAM_DEGRADED
    if (gameOk || chatOk) {
      return 'PROGRAM_DEGRADED';
    }

    // 4. Authenticated, but neither dynamic source is ready yet -> PROGRAM_SAFE
    return 'PROGRAM_SAFE';
  }

  /**
   * Evaluates if dynamic layers are allowed into the live PROGRAM composition.
   */
  public isDynamicLayerAllowed(layerType: 'game' | 'chat'): boolean {
    if (this.currentState === 'PROGRAM_AUTH_REQUIRED' || this.currentState === 'PROGRAM_SAFE') {
      return false; // Absolute safety gate: static content only
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
