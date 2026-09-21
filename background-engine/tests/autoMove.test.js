import test from 'node:test';
import assert from 'node:assert/strict';

class AutoMoveSequencerMock {
  constructor() {
    this.sequence = ['P1', 'P2', 'P3'];
    this.currentPosition = 'P1';
    this.remainingSeconds = 30;
    this.state = 'STOPPED';
    this.loop = true;
  }

  getNextPosition() {
    const idx = this.sequence.indexOf(this.currentPosition);
    return this.sequence[(idx + 1) % this.sequence.length];
  }

  getPreviousPosition() {
    const idx = this.sequence.indexOf(this.currentPosition);
    return this.sequence[(idx - 1 + this.sequence.length) % this.sequence.length];
  }

  next() {
    this.currentPosition = this.getNextPosition();
    this.remainingSeconds = 30;
  }

  prev() {
    this.currentPosition = this.getPreviousPosition();
    this.remainingSeconds = 30;
  }
}

test('AutoMove - Sequence transitions P1 -> P2 -> P3 -> P1', () => {
  const seq = new AutoMoveSequencerMock();
  assert.equal(seq.currentPosition, 'P1');

  seq.next();
  assert.equal(seq.currentPosition, 'P2');

  seq.next();
  assert.equal(seq.currentPosition, 'P3');

  seq.next();
  assert.equal(seq.currentPosition, 'P1', 'Should loop back to P1');
});

test('AutoMove - Previous transitions P1 -> P3 -> P2 -> P1', () => {
  const seq = new AutoMoveSequencerMock();
  assert.equal(seq.currentPosition, 'P1');

  seq.prev();
  assert.equal(seq.currentPosition, 'P3');

  seq.prev();
  assert.equal(seq.currentPosition, 'P2');
});
