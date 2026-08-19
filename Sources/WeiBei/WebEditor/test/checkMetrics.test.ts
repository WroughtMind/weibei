import assert from 'node:assert/strict';
import test from 'node:test';
import {
  addEditorMetric,
  createEditorCheckMetrics,
  metricNames,
  resetEditorCheckMetrics,
} from '../src/checkMetrics';

test('check metrics start at zero and count only requested work', () => {
  const metrics = createEditorCheckMetrics();
  assert.deepEqual(Object.keys(metrics), metricNames);
  assert.ok(Object.values(metrics).every((value) => value === 0));

  addEditorMetric(metrics, 'transactions');
  addEditorMetric(metrics, 'bridgeBytes', 128);

  assert.equal(metrics.transactions, 1);
  assert.equal(metrics.bridgeBytes, 128);
  addEditorMetric(null, 'transactions');

  resetEditorCheckMetrics(metrics);
  assert.ok(Object.values(metrics).every((value) => value === 0));
});
