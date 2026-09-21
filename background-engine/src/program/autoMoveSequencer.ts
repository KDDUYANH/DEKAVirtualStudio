import { EventEmitter } from 'events';
import { AutoMoveState, PositionId } from '../main/types.js';
import { PositionEngine } from './positionEngine.js';

export interface AutoMoveStatus {
  state: AutoMoveState;
  currentPosition: PositionId;
  nextPosition: PositionId;
  timeRemainingSeconds: number;
  totalDurationSeconds: number;
  loop: boolean;
}

export class AutoMoveSequencer extends EventEmitter {
  private positionEngine: PositionEngine;
  private state: AutoMoveState = 'STOPPED';
  private loop: boolean = true;
  private remainingSeconds: number = 30;
  private timer: NodeJS.Timeout | null = null;

  private sequence: PositionId[] = ['P1', 'P2', 'P3'];

  constructor(positionEngine: PositionEngine, autoStart: boolean = false, loop: boolean = true) {
    super();
    this.positionEngine = positionEngine;
    this.loop = loop;
    this.resetTimerForCurrent();

    if (autoStart) {
      this.start();
    }
  }

  public getStatus(): AutoMoveStatus {
    const current = this.positionEngine.getActivePosition();
    const next = this.getNextPosition(current);
    const total = this.positionEngine.getActivePreset().durationSeconds || 30;

    return {
      state: this.state,
      currentPosition: current,
      nextPosition: next,
      timeRemainingSeconds: this.remainingSeconds,
      totalDurationSeconds: total,
      loop: this.loop,
    };
  }

  private getNextPosition(current: PositionId): PositionId {
    const idx = this.sequence.indexOf(current);
    const nextIdx = (idx + 1) % this.sequence.length;
    return this.sequence[nextIdx];
  }

  private getPreviousPosition(current: PositionId): PositionId {
    const idx = this.sequence.indexOf(current);
    const prevIdx = (idx - 1 + this.sequence.length) % this.sequence.length;
    return this.sequence[prevIdx];
  }

  private resetTimerForCurrent(): void {
    const preset = this.positionEngine.getActivePreset();
    this.remainingSeconds = preset.durationSeconds || 30;
  }

  public start(): void {
    if (this.state === 'RUNNING') return;
    this.state = 'RUNNING';
    this.startTicker();
    console.log('[AutoMove] Started auto-move sequencer.');
    this.emitStatus();
  }

  public pause(): void {
    if (this.state !== 'RUNNING') return;
    this.state = 'PAUSED';
    this.stopTicker();
    console.log('[AutoMove] Paused auto-move sequencer.');
    this.emitStatus();
  }

  public stop(): void {
    this.state = 'STOPPED';
    this.stopTicker();
    this.resetTimerForCurrent();
    console.log('[AutoMove] Stopped auto-move sequencer.');
    this.emitStatus();
  }

  public next(): void {
    const current = this.positionEngine.getActivePosition();
    const next = this.getNextPosition(current);
    this.positionEngine.setPosition(next);
    this.resetTimerForCurrent();
    this.emitStatus();
  }

  public previous(): void {
    const current = this.positionEngine.getActivePosition();
    const prev = this.getPreviousPosition(current);
    this.positionEngine.setPosition(prev);
    this.resetTimerForCurrent();
    this.emitStatus();
  }

  public setLoop(enabled: boolean): void {
    this.loop = enabled;
    this.emitStatus();
  }

  private startTicker(): void {
    this.stopTicker();
    this.timer = setInterval(() => {
      if (this.state !== 'RUNNING') return;

      this.remainingSeconds--;
      if (this.remainingSeconds <= 0) {
        const current = this.positionEngine.getActivePosition();
        const next = this.getNextPosition(current);

        // Check loop condition
        if (!this.loop && next === 'P1') {
          this.stop();
          return;
        }

        this.positionEngine.setPosition(next);
        this.resetTimerForCurrent();
      }

      this.emitStatus();
    }, 1000);
  }

  private stopTicker(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private emitStatus(): void {
    this.emit('tick', this.getStatus());
  }

  public destroy(): void {
    this.stopTicker();
  }
}
