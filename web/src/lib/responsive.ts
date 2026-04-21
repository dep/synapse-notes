export const MOBILE_BREAKPOINT = 900
export const WIDE_BREAKPOINT = 1250

export function isMobile(width: number): boolean {
  return width < MOBILE_BREAKPOINT
}

export function defaultSidebarVisible(width: number): boolean {
  return width >= MOBILE_BREAKPOINT
}

export function defaultPreviewVisible(width: number): boolean {
  return width >= WIDE_BREAKPOINT
}

type Side = 'above' | 'below'

function sideRelativeTo(width: number, breakpoint: number): Side {
  return width >= breakpoint ? 'above' : 'below'
}

export function crossedBreakpoint(
  prevWidth: number,
  nextWidth: number,
  breakpoint: number,
): boolean {
  return sideRelativeTo(prevWidth, breakpoint) !== sideRelativeTo(nextWidth, breakpoint)
}

export function resolveVisible(
  width: number,
  breakpoint: number,
  override: boolean | null,
): boolean {
  if (override === null) return width >= breakpoint
  return override
}
