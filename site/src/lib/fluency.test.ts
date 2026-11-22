import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fluency, type Outcome } from './fluency.ts';

const run = (...parts: [Outcome, number][]) => parts.flatMap(([o, n]) => Array<Outcome>(n).fill(o));

test('stages follow the README table', () => {
  assert.equal(fluency([]), 'learning');
  assert.equal(fluency(run(['hit', 4])), 'learning');
  assert.equal(fluency(run(['hit', 5])), 'practicing');
  assert.equal(fluency(run(['miss', 5], ['hit', 5])), 'practicing');
  assert.equal(fluency(run(['miss', 2], ['hit', 8])), 'fluent');
  assert.equal(fluency(run(['miss', 1], ['hit', 19])), 'learned');
  assert.equal(fluency(run(['miss', 2], ['hit', 18])), 'fluent');
  assert.equal(fluency(run(['miss', 30], ['hit', 20])), 'learned'); // only the last 20 count
});

test('the demo counts each switch four times: five hotkey presses teach an app', () => {
  const after = (hits: number) => fluency(run(['hit', hits * 4]));
  assert.deepEqual([1, 2, 3, 4, 5].map(after), ['learning', 'practicing', 'fluent', 'fluent', 'learned']);
});
