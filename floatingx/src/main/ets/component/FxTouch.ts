import { FxPoint, FxGestureMode } from '../core/FxTypes';
export interface FxTouchClock { now(): number; }
export class FxWallTouchClock implements FxTouchClock { now(): number { return Date.now(); } }
export interface FxPointer { id: number; x: number; y: number; timeMs: number; }
export type FxTouchKind = 'none' | 'drag' | 'click' | 'longPress' | 'end';
export interface FxTouchResult { kind: FxTouchKind; position: FxPoint; }
/** Coordinates are absolute vp: moving the rendered content cannot feed back into drag deltas. */
export class FxTouch {
 private primary?: FxPointer;
 private origin: FxPoint = {x:0,y:0};
 private position: FxPoint = {x:0,y:0};
 private displaced: boolean = false;
 private longPressed: boolean = false;
 private lastClick: number = -Infinity;
 private clickCandidate: boolean = false;
 private downTime: number = 0;
 private clock: FxTouchClock;
 private mode: string;
 private thresholdVp: number;
 private clickIntervalMs: number;
 private longPressMs: number;
 private gestureMode: FxGestureMode;
 constructor(mode: string, thresholdVp: number, clickIntervalMs: number, longPressMs: number, gestureMode: FxGestureMode = FxGestureMode.LEGACY, clock: FxTouchClock = new FxWallTouchClock()) {
   this.clock=clock;
   this.gestureMode=gestureMode;
   this.mode=mode; this.thresholdVp=thresholdVp; this.clickIntervalMs=clickIntervalMs; this.longPressMs=longPressMs;
 }
 down(pointer: FxPointer, position: FxPoint = {x:0,y:0}, hasClickListener: boolean = true): FxTouchResult {
   if (this.mode === 'DisplayOnly' || this.mode === 'display-only' || this.primary !== undefined) return this.result('none');
   this.primary = {id:pointer.id,x:pointer.x,y:pointer.y,timeMs:pointer.timeMs};
   this.origin = {x:position.x,y:position.y}; this.position = {x:position.x,y:position.y};
   this.clickCandidate=hasClickListener;this.downTime=this.clock.now();
   this.displaced = false; this.longPressed = false; return this.result('none');
 }
 /** Android interception observes displacement without performing a parent MOVE. */
 shouldIntercept(pointer: FxPointer): boolean {
   const p=this.primary;
   return p!==undefined && p.id===pointer.id && this.mode!=='ClickOnly' && this.mode!=='click-only' &&
     (Math.abs(pointer.x-p.x)>=this.thresholdVp || Math.abs(pointer.y-p.y)>=this.thresholdVp);
 }
 /** Called only after an actual click callback is selected for delivery. */
 commitClick(): void {if(this.gestureMode===FxGestureMode.ANDROID_2)this.lastClick=this.clock.now();}
 move(pointer: FxPointer): FxTouchResult {
   const primary = this.primary;
   if (primary === undefined || pointer.id !== primary.id || this.longPressed) return this.result('none');
   const dx = pointer.x-primary.x; const dy = pointer.y-primary.y;
   if(this.gestureMode===FxGestureMode.ANDROID_2) {
     this.clickCandidate=this.clickCandidate && Math.abs(dx)<this.thresholdVp && Math.abs(dy)<this.thresholdVp;
     if(this.mode==='ClickOnly' || this.mode==='click-only')return this.result('none');
     this.position={x:this.origin.x+dx,y:this.origin.y+dy};return this.result('drag');
   }
   if (Math.sqrt(dx*dx+dy*dy)>this.thresholdVp) this.displaced = true;
   if (this.displaced) {
     if (this.mode === 'ClickOnly' || this.mode === 'click-only') return this.result('none');
     this.position = {x:this.origin.x+dx,y:this.origin.y+dy}; return this.result('drag');
   }
   if (this.gestureMode === FxGestureMode.LEGACY && pointer.timeMs-primary.timeMs >= this.longPressMs) {
     this.longPressed = true; return this.result('longPress');
   }
   return this.result('none');
 }
 up(pointer: FxPointer): FxTouchResult {
   if (this.gestureMode === FxGestureMode.ANDROID_2) {
     const now=this.clock.now();const duration=now-this.downTime;
     let kind: FxTouchKind='end';
     if(this.clickCandidate) {
       if(duration<150 && now-this.lastClick>=this.clickIntervalMs)kind='click';
       else if(duration>=500)kind='longPress';
     }
     this.primary=undefined;this.clickCandidate=false;return this.result(kind);
   }
   if (this.primary === undefined || pointer.id !== this.primary.id) return this.result('none');
   const update = this.move(pointer);
   const kind = update.kind === 'longPress' ? 'longPress' :
     (!this.displaced && !this.longPressed && pointer.timeMs-this.lastClick>=this.clickIntervalMs ? 'click' : 'end');
   if (kind === 'click') this.lastClick = pointer.timeMs;
   this.primary = undefined; return this.result(kind);
 }
 cancel(): FxTouchResult {
   const active = this.primary !== undefined; this.primary = undefined;this.clickCandidate=false; return this.result(active ? 'end':'none');
 }
 private result(kind: FxTouchKind): FxTouchResult {
   return {kind:kind,position:{x:this.position.x,y:this.position.y}};
 }
}
