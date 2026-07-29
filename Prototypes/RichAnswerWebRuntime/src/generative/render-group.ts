export type RenderGroupResourceLimits = {
  maxLogicalPlanBytes: number;
  maxTrustedAssets: number;
  maxTrustedAssetBytes: number;
  maxTrustedAssetTotalBytes: number;
};

export type RenderGroupResourceUsage = {
  logicalPlanBytes: number;
  trustedAssetBytes: number[];
};

export type RichAnswerRuntimeFailureScope =
  | "program-entry"
  | "renderer-entry"
  | "entry-error-boundary"
  | "runtime-startup"
  | "navigation"
  | "host-transport";

export function runtimeFailureIsFatal(scope: RichAnswerRuntimeFailureScope) {
  return scope === "runtime-startup"
    || scope === "navigation"
    || scope === "host-transport";
}

export type IndexedRenderGroupItem<T> = {
  index: number;
  value: T;
};

export type ResourceIndexedRenderGroupItem<T> = IndexedRenderGroupItem<T> & {
  usage: RenderGroupResourceUsage;
};

export type RenderGroupResourceRejection<T> = ResourceIndexedRenderGroupItem<T> & {
  reason:
    | "logical_plan_bytes"
    | "trusted_asset_count"
    | "trusted_asset_bytes"
    | "trusted_asset_total_bytes";
};

export function admitRenderGroupItems<T>(
  items: ResourceIndexedRenderGroupItem<T>[],
  limits: RenderGroupResourceLimits,
) {
  const accepted: ResourceIndexedRenderGroupItem<T>[] = [];
  const rejected: RenderGroupResourceRejection<T>[] = [];
  let logicalPlanBytes = 0;
  let trustedAssetCount = 0;
  let trustedAssetTotalBytes = 0;

  [...items].sort((left, right) => left.index - right.index).forEach((item) => {
    const invalidTrustedAsset = item.usage.trustedAssetBytes.some((bytes) =>
      !Number.isSafeInteger(bytes) || bytes < 0 || bytes > limits.maxTrustedAssetBytes);
    const nextLogicalPlanBytes = logicalPlanBytes + item.usage.logicalPlanBytes;
    const nextTrustedAssetCount = trustedAssetCount + item.usage.trustedAssetBytes.length;
    const itemTrustedAssetTotalBytes = item.usage.trustedAssetBytes.reduce(
      (sum, bytes) => sum + bytes,
      0,
    );
    const nextTrustedAssetTotalBytes = trustedAssetTotalBytes + itemTrustedAssetTotalBytes;
    const reason = invalidTrustedAsset
      ? "trusted_asset_bytes"
      : !Number.isSafeInteger(item.usage.logicalPlanBytes)
          || item.usage.logicalPlanBytes < 1
          || !Number.isSafeInteger(nextLogicalPlanBytes)
          || nextLogicalPlanBytes > limits.maxLogicalPlanBytes
        ? "logical_plan_bytes"
        : nextTrustedAssetCount > limits.maxTrustedAssets
          ? "trusted_asset_count"
          : !Number.isSafeInteger(nextTrustedAssetTotalBytes)
              || nextTrustedAssetTotalBytes > limits.maxTrustedAssetTotalBytes
            ? "trusted_asset_total_bytes"
            : null;

    if (reason) {
      rejected.push({ ...item, reason });
      return;
    }
    logicalPlanBytes = nextLogicalPlanBytes;
    trustedAssetCount = nextTrustedAssetCount;
    trustedAssetTotalBytes = nextTrustedAssetTotalBytes;
    accepted.push(item);
  });

  return {
    accepted,
    rejected,
    totals: {
      logicalPlanBytes,
      trustedAssetCount,
      trustedAssetTotalBytes,
    },
  };
}

export function mergeIndexedRenderGroupItems<T>(
  ...collections: Array<Array<IndexedRenderGroupItem<T>>>
) {
  return collections
    .flat()
    .map((item, sequence) => ({ ...item, sequence }))
    .sort((left, right) => left.index - right.index || left.sequence - right.sequence)
    .map((item) => item.value);
}
