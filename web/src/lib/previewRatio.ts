export const DEFAULT_PREVIEW_RATIO = 0.5
export const MIN_PANE_RATIO = 0.2
export const MAX_PANE_RATIO = 0.8

export function previewRatioStorageKey(repoFullName: string): string {
  return `synapse_preview_ratio:${repoFullName}`
}

export function clampRatio(ratio: number): number {
  if (!Number.isFinite(ratio)) return DEFAULT_PREVIEW_RATIO
  if (ratio < MIN_PANE_RATIO) return MIN_PANE_RATIO
  if (ratio > MAX_PANE_RATIO) return MAX_PANE_RATIO
  return ratio
}

export function parseRatio(raw: string | null): number {
  if (!raw) return DEFAULT_PREVIEW_RATIO
  const num = Number(raw)
  if (!Number.isFinite(num)) return DEFAULT_PREVIEW_RATIO
  return clampRatio(num)
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem'>

export function loadPreviewRatio(
  repoFullName: string,
  storage: Storage = localStorage,
): number {
  return parseRatio(storage.getItem(previewRatioStorageKey(repoFullName)))
}

export function savePreviewRatio(
  repoFullName: string,
  ratio: number,
  storage: Storage = localStorage,
): void {
  storage.setItem(previewRatioStorageKey(repoFullName), String(clampRatio(ratio)))
}
