/** Public geometry uses vp in every scope. */
export interface FxPoint { x: number; y: number; }
export interface FxSize { width: number; height: number; }
export interface FxInsets { left: number; top: number; right: number; bottom: number; }
export interface FxBounds { minX: number; maxX: number; minY: number; maxY: number; }
export interface FxViewport { size: FxSize; insets: FxInsets; }
export interface FxProjection {
  position: FxPoint;
  visibleSize: FxSize;
  contentOffset: FxPoint;
}

export enum FxGravity {
  TOP_LEFT = 'top-left', TOP_CENTER = 'top-center', TOP_RIGHT = 'top-right',
  CENTER_LEFT = 'center-left', CENTER = 'center', CENTER_RIGHT = 'center-right',
  BOTTOM_LEFT = 'bottom-left', BOTTOM_CENTER = 'bottom-center', BOTTOM_RIGHT = 'bottom-right'
}
export enum FxEdgeAdsorb {
  LEFT = 'left', RIGHT = 'right', TOP = 'top', BOTTOM = 'bottom',
  LEFT_RIGHT = 'left-right', TOP_BOTTOM = 'top-bottom'
}
export enum FxDisplayMode { Normal = 'normal', ClickOnly = 'click-only', DisplayOnly = 'display-only' }
export enum FxAnimationCurve {
  LINEAR = 'linear', EASE = 'ease', EASE_IN = 'ease-in', EASE_OUT = 'ease-out', EASE_IN_OUT = 'ease-in-out'
}
export interface FxAnimationConfig {
  enabled: boolean;
  durationMs: number;
  curve: FxAnimationCurve;
}
export enum FxEdge { NONE = 'none', LEFT = 'left', RIGHT = 'right', TOP = 'top', BOTTOM = 'bottom' }
/** Version 1 stores logical full-content coordinates, never the clipped window position. */
export interface FxPositionRecord {
  version: number;
  position: FxPoint;
  viewport: FxSize;
  edge: FxEdge;
}

/** CONTENT preserves the original Harmony projection; ANDROID_2 uses FloatingX 2.x movement bounds. */
export enum FxBoundaryMode { CONTENT = 'content', ANDROID_2 = 'android-2' }
/** Detached values in vp; density converts to native px. Initial declared sizes are not measured sizes. */
export interface FxGeometrySnapshot {
  instanceId: number;
  layoutVersion: number;
  measured: boolean;
  coordinateSpace: string;
  density: number;
  viewport: FxViewport;
  content: FxSize;
  requestedPosition: FxPoint;
  position: FxPoint;
  projection: FxProjection;
}
export type FxLayoutListener = (snapshot: FxGeometrySnapshot) => void;
export enum FxTouchPhase { DOWN = 'down', MOVE = 'move', UP = 'up', CANCEL = 'cancel' }
export enum FxTouchCancelReason {
  SYSTEM = 'system', HIDDEN = 'hidden', DESTROYED = 'destroyed', HOST_CHANGED = 'host-changed',
  LAYOUT_CHANGED = 'layout-changed', CONFIG_CHANGED = 'config-changed', MOVED = 'moved'
}
export interface FxTouchSnapshot {
  phase: FxTouchPhase;
  pointerId: number;
  startPointer: FxPoint;
  pointer: FxPoint;
  delta: FxPoint;
  startPosition: FxPoint;
  position: FxPoint;
  dragged: boolean;
  cancelReason?: FxTouchCancelReason;
}
export enum FxReleaseDecision { DEFAULT = 'default', CONSUMED = 'consumed' }

/** LEGACY preserves the original surface; ANDROID_2 uses the 2.3.7 axis/release timing contract. */
export enum FxGestureMode { LEGACY = 'legacy', ANDROID_2 = 'android-2' }
/** DEFAULT retains native creation policy; NON_FOCUSABLE matches Android's default overlay flags. */
export enum FxFocusPolicy { DEFAULT = 'default', NON_FOCUSABLE = 'non-focusable' }

/** HOST preserves the measured host; AVOID_SYSTEM clips only intersecting system avoid areas. */
export enum FxSafeAreaPolicy { HOST = 'host', AVOID_SYSTEM = 'avoid-system', EXTEND = 'extend' }
