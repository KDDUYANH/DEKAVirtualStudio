import { EventEmitter } from 'events';
import { GameSourceState, ChatSourceState, TargetConfig } from './types.js';

export interface RecoveryStatus {
  game: {
    state: GameSourceState;
    attempts: number;
    maxAttempts: number;
    currentBackoffMs: number;
    lastError?: string;
  };
  chat: {
    state: ChatSourceState;
    attempts: number;
    maxAttempts: number;
    currentBackoffMs: number;
    lastError?: string;
  };
}

const BACKOFF_STEPS = [1000, 2000, 5000, 10000, 20000, 30000];
const MAX_ATTEMPTS = 5;

export class SourceRecoveryManager extends EventEmitter {
  private targets: TargetConfig;
  private status: RecoveryStatus;
  private gameTimer: NodeJS.Timeout | null = null;
  private chatTimer: NodeJS.Timeout | null = null;

  constructor(initialTargets: TargetConfig) {
    super();
    this.targets = { ...initialTargets };
    this.status = {
      game: {
        state: 'STARTING',
        attempts: 0,
        maxAttempts: MAX_ATTEMPTS,
        currentBackoffMs: BACKOFF_STEPS[0],
      },
      chat: {
        state: 'STARTING',
        attempts: 0,
        maxAttempts: MAX_ATTEMPTS,
        currentBackoffMs: BACKOFF_STEPS[0],
      },
    };
  }

  public getStatus(): RecoveryStatus {
    return JSON.parse(JSON.stringify(this.status));
  }

  public getTargets(): TargetConfig {
    return { ...this.targets };
  }

  public updateTargets(newTargets: Partial<TargetConfig>): void {
    this.targets = { ...this.targets, ...newTargets };
    // Trigger verification/reconnect with new targets
    this.resetGameRecovery();
    this.resetChatRecovery();
  }

  // ==========================================================================
  // GAME RECOVERY PIPELINE
  // ==========================================================================
  public setGameState(state: GameSourceState, errorMsg?: string): void {
    if (this.status.game.state === state) return;
    this.status.game.state = state;
    if (errorMsg) this.status.game.lastError = errorMsg;

    console.log(`[SourceRecovery] Game State -> ${state}`);
    this.emit('game-state-changed', {
      state,
      error: errorMsg,
      attempts: this.status.game.attempts,
    });

    if (state === 'ROUTE_LOST' || state === 'DISCONNECTED' || state === 'BUFFERING') {
      this.triggerGameRecovery();
    } else if (state === 'LIVE' || state === 'READY') {
      this.resetGameRecoverySuccess();
    }
  }

  public triggerGameRecovery(): void {
    if (this.gameTimer) return; // Recovery cycle already scheduled
    if (this.status.game.attempts >= MAX_ATTEMPTS) {
      this.setGameState('FAILED', 'Maximum automatic recovery attempts reached (5/5).');
      return;
    }

    const delay = BACKOFF_STEPS[Math.min(this.status.game.attempts, BACKOFF_STEPS.length - 1)];
    this.status.game.attempts++;
    this.status.game.currentBackoffMs = delay;
    this.status.game.state = 'RECONNECTING';

    console.log(`[SourceRecovery] Scheduling Game Recovery (Attempt ${this.status.game.attempts}/${MAX_ATTEMPTS}) in ${delay}ms...`);
    this.emit('game-recovering', { attempt: this.status.game.attempts, delay });

    this.gameTimer = setTimeout(() => {
      this.gameTimer = null;
      this.executeGameRecoveryStep();
    }, delay);
  }

  private executeGameRecoveryStep(): void {
    console.log(`[SourceRecovery] Executing Game recovery -> Re-navigating to ${this.targets.selectedGameUrl}`);
    // Emit event requesting Game WebView to navigate to target URL and verify
    this.emit('request-game-navigate', {
      targetUrl: this.targets.selectedGameUrl,
      targetId: this.targets.selectedGameId,
    });
  }

  public resetGameRecoverySuccess(): void {
    if (this.gameTimer) {
      clearTimeout(this.gameTimer);
      this.gameTimer = null;
    }
    this.status.game.attempts = 0;
    this.status.game.currentBackoffMs = BACKOFF_STEPS[0];
    this.status.game.lastError = undefined;
    this.targets.lastKnownGoodGameUrl = this.targets.selectedGameUrl;
  }

  public resetGameRecovery(): void {
    if (this.gameTimer) {
      clearTimeout(this.gameTimer);
      this.gameTimer = null;
    }
    this.status.game.attempts = 0;
    this.status.game.currentBackoffMs = BACKOFF_STEPS[0];
    this.triggerGameRecovery();
  }

  // ==========================================================================
  // CHAT RECOVERY PIPELINE
  // ==========================================================================
  public setChatState(state: ChatSourceState, errorMsg?: string): void {
    if (this.status.chat.state === state) return;
    this.status.chat.state = state;
    if (errorMsg) this.status.chat.lastError = errorMsg;

    console.log(`[SourceRecovery] Chat State -> ${state}`);
    this.emit('chat-state-changed', {
      state,
      error: errorMsg,
      attempts: this.status.chat.attempts,
    });

    if (state === 'ROUTE_LOST' || state === 'DISCONNECTED') {
      this.triggerChatRecovery();
    } else if (state === 'CONNECTED' || state === 'READY') {
      this.resetChatRecoverySuccess();
    }
  }

  public triggerChatRecovery(): void {
    if (this.chatTimer) return;
    if (this.status.chat.attempts >= MAX_ATTEMPTS) {
      this.setChatState('FAILED', 'Maximum automatic recovery attempts reached (5/5).');
      return;
    }

    const delay = BACKOFF_STEPS[Math.min(this.status.chat.attempts, BACKOFF_STEPS.length - 1)];
    this.status.chat.attempts++;
    this.status.chat.currentBackoffMs = delay;
    this.status.chat.state = 'RECONNECTING';

    console.log(`[SourceRecovery] Scheduling Chat Recovery (Attempt ${this.status.chat.attempts}/${MAX_ATTEMPTS}) in ${delay}ms...`);
    this.emit('chat-recovering', { attempt: this.status.chat.attempts, delay });

    this.chatTimer = setTimeout(() => {
      this.chatTimer = null;
      this.executeChatRecoveryStep();
    }, delay);
  }

  private executeChatRecoveryStep(): void {
    console.log(`[SourceRecovery] Executing Chat recovery -> Re-connecting to ${this.targets.selectedChatUrl}`);
    this.emit('request-chat-reconnect', {
      targetUrl: this.targets.selectedChatUrl,
      targetId: this.targets.selectedChatId,
    });
  }

  public resetChatRecoverySuccess(): void {
    if (this.chatTimer) {
      clearTimeout(this.chatTimer);
      this.chatTimer = null;
    }
    this.status.chat.attempts = 0;
    this.status.chat.currentBackoffMs = BACKOFF_STEPS[0];
    this.status.chat.lastError = undefined;
    this.targets.lastKnownGoodChatUrl = this.targets.selectedChatUrl;
  }

  public resetChatRecovery(): void {
    if (this.chatTimer) {
      clearTimeout(this.chatTimer);
      this.chatTimer = null;
    }
    this.status.chat.attempts = 0;
    this.status.chat.currentBackoffMs = BACKOFF_STEPS[0];
    this.triggerChatRecovery();
  }

  public destroy(): void {
    if (this.gameTimer) clearTimeout(this.gameTimer);
    if (this.chatTimer) clearTimeout(this.chatTimer);
  }
}
