export const metricNames = [
  'transactions',
  'fullSerializations',
  'bridgeMessages',
  'bridgeBytes',
  'decorationNodes',
  'decorationCacheHits',
  'katexRenders',
  'mermaidRenders',
  'imageScans',
  'imageNodeUpdates',
  'codeTokenizations',
  'outlineReports',
] as const;

export type EditorMetricName = typeof metricNames[number];
export type EditorCheckMetrics = Record<EditorMetricName, number>;

export const createEditorCheckMetrics = (): EditorCheckMetrics => Object.fromEntries(
  metricNames.map((name) => [name, 0]),
) as EditorCheckMetrics;

export const addEditorMetric = (
  metrics: EditorCheckMetrics | null,
  name: EditorMetricName,
  amount = 1,
) => {
  if (metrics) metrics[name] += amount;
};

export const resetEditorCheckMetrics = (metrics: EditorCheckMetrics | null) => {
  if (!metrics) return;
  for (const name of metricNames) metrics[name] = 0;
};
