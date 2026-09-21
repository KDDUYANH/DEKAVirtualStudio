import test from 'node:test';
import assert from 'node:assert/strict';

const BACKOFF_STEPS = [1000, 2000, 5000, 10000, 20000, 30000];
const MAX_ATTEMPTS = 5;

class RecoveryTracker {
  constructor() {
    this.attempts = 0;
    this.state = 'STARTING';
    this.currentBackoffMs = BACKOFF_STEPS[0];
  }

  triggerRecovery() {
    if (this.attempts >= MAX_ATTEMPTS) {
      this.state = 'FAILED';
      return false;
    }
    const delay = BACKOFF_STEPS[Math.min(this.attempts, BACKOFF_STEPS.length - 1)];
    this.attempts++;
    this.currentBackoffMs = delay;
    this.state = 'RECONNECTING';
    return true;
  }

  markSuccess() {
    this.attempts = 0;
    this.currentBackoffMs = BACKOFF_STEPS[0];
    this.state = 'LIVE';
  }
}

test('RecoveryTracker - Correct exponential backoff progression', () => {
  const tracker = new RecoveryTracker();

  assert.equal(tracker.triggerRecovery(), true);
  assert.equal(tracker.attempts, 1);
  assert.equal(tracker.currentBackoffMs, 1000);

  assert.equal(tracker.triggerRecovery(), true);
  assert.equal(tracker.attempts, 2);
  assert.equal(tracker.currentBackoffMs, 2000);

  assert.equal(tracker.triggerRecovery(), true);
  assert.equal(tracker.attempts, 3);
  assert.equal(tracker.currentBackoffMs, 5000);

  assert.equal(tracker.triggerRecovery(), true);
  assert.equal(tracker.attempts, 4);
  assert.equal(tracker.currentBackoffMs, 10000);

  assert.equal(tracker.triggerRecovery(), true);
  assert.equal(tracker.attempts, 5);
  assert.equal(tracker.currentBackoffMs, 20000);

  // 6th attempt must FAIL (max 5 attempts)
  assert.equal(tracker.triggerRecovery(), false);
  assert.equal(tracker.state, 'FAILED');
});

test('RecoveryTracker - Successful recovery resets attempts and backoff', () => {
  const tracker = new RecoveryTracker();
  tracker.triggerRecovery();
  tracker.triggerRecovery();
  assert.equal(tracker.attempts, 2);

  tracker.markSuccess();
  assert.equal(tracker.attempts, 0);
  assert.equal(tracker.currentBackoffMs, 1000);
  assert.equal(tracker.state, 'LIVE');
});
