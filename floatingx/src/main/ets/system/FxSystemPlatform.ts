import { FxPlatform, FxScope, FxEvent, FxEventType, FxEventCallback } from '../core/FxPlatform';
import { FxController } from '../core/FxController';
import { FxConfig } from '../core/FxConfig';
import { FxError } from '../core/FxError';
import { FxPoint, FxSize, FxProjection, FxDisplayMode, FxAnimationCurve, FxGeometrySnapshot, FxLayoutListener, FxTouchCancelReason, FxBoundaryMode, FxGestureMode, FxFocusPolicy, FxSafeAreaPolicy } from '../core/FxTypes';
import { FxGeometryInput, initial, clamp, bounds, project, logicalEdge, remap, snapshot, resizePosition } from '../geometry/FxGeometry';
import { FxAnimation } from '../component/FxAnimation';
import { FxNativeWindow, FxWindowFactory, FxSystemView } from './FxNativeWindow';
export interface FxFrameClock { now(): number; wait(): Promise<void>; cancel(): void; }
class FxNativeClock implements FxFrameClock {
  private timer: number = -1; private finish?: () => void;
  now(): number { return Date.now(); }
  wait(): Promise<void> { return new Promise<void>((resolve) => {this.finish=resolve; this.timer=setTimeout(() => {this.finish=undefined;resolve();},16);}); }
  cancel(): void {clearTimeout(this.timer);const finish=this.finish;this.finish=undefined;if(finish!==undefined)finish();}
}
export interface FxFallbackPlatform extends FxPlatform {bindController?(controller: FxController): void;getGeometry?(): FxGeometryInput;}
export type FxFallbackFactory = () => FxFallbackPlatform;
/** Permission/capability strategy and transactional native projection; no SDK access in constructor. */
export class FxSystemPlatform implements FxPlatform {
  actualScope: FxScope = FxScope.SYSTEM;
  private factory: FxWindowFactory; private input: FxGeometryInput;
  private fallbackFactory?: FxFallbackFactory; private fallback?: FxFallbackPlatform;
  private fallbackCreated: boolean = false; private fallbackCause?: FxError;
  private onEvent?: FxEventCallback; private native?: FxNativeWindow; private view?: FxSystemView;
  private controller?: FxController; private releaseNative?: () => void; private releaseFallback?: () => void;
  private listeners: ((type: FxEventType) => void)[] = [];
  private position: FxPoint = {x:0,y:0}; private projection: FxProjection;
  private positioned: boolean = false; private destroyed: boolean = false;
  private tail: Promise<void> = Promise.resolve(); private animation: FxAnimation = new FxAnimation(); private clock: FxFrameClock;
  private layoutVersion: number = 0;
  private measured: boolean = false;
  private initialMeasurementPending: boolean = true;
  private releaseVisibility?: () => void;
  private density: number = 1;
  private requestedPosition: FxPoint = {x:0,y:0};
  private layoutListeners: FxLayoutListener[] = [];
  private releaseFallbackLayout?: () => void;
  private layoutCompletion: Promise<void> = Promise.resolve();
  private frameCompletion: Promise<void> = Promise.resolve();
  private frameRevision: number = 0;
  private pendingFrame?: FxPoint; private frameRunning: boolean = false;
  constructor(factory: FxWindowFactory, input: FxGeometryInput, fallbackFactory?: FxFallbackFactory, onEvent?: FxEventCallback, clock: FxFrameClock = new FxNativeClock()) {
    this.factory=factory;this.input={viewport:input.viewport,content:input.content,config:input.config===undefined?new FxConfig():input.config.copy()};
    this.fallbackFactory=fallbackFactory;this.onEvent=onEvent;this.clock=clock;this.projection=project(initial(this.input),this.input);
  }
  bindController(controller: FxController): void {this.controller=controller;if(this.view!==undefined)this.view.bindController(controller);}
  attachView(view: FxSystemView): void {if(this.destroyed)return;this.view=view;if(this.controller!==undefined)view.bindController(this.controller);this.lifecycle(FxEventType.ATTACH);}
  detachView(): void {this.view=undefined;this.lifecycle(FxEventType.DETACH);}
  subscribeLifecycle(listener: (type: FxEventType) => void): () => void {this.listeners.push(listener);return () => {const i=this.listeners.indexOf(listener);if(i>=0)this.listeners.splice(i,1);};}
  isActuallyVisible(): boolean {
    if(this.fallback!==undefined)return this.fallback.isActuallyVisible===undefined || this.fallback.isActuallyVisible();
    return this.native!==undefined && this.native.terminated!==true && (this.native.isShowing===undefined || this.native.isShowing());
  }
  isHostVisible(): boolean {return !this.destroyed && (this.fallback===undefined || this.fallback.isHostVisible===undefined || this.fallback.isHostVisible());}
  isReadyToShow(): boolean {return this.fallback!==undefined ? this.fallback.isReadyToShow===undefined || this.fallback.isReadyToShow():this.native!==undefined && (!this.native.requiresView || this.view!==undefined);}
  getPosition(): FxPoint {return this.fallback!==undefined && this.fallback.getPosition!==undefined ? this.fallback.getPosition():{x:this.position.x,y:this.position.y};}
  getGeometry(): FxGeometryInput {return this.fallback!==undefined && this.fallback.getGeometry!==undefined?this.fallback.getGeometry():this.input;}
  getGeometrySnapshot(): FxGeometrySnapshot {
    if(this.fallback!==undefined && this.fallback.getGeometrySnapshot!==undefined)return this.fallback.getGeometrySnapshot();
    return snapshot(this.input,this.position,this.projection,this.requestedPosition,this.layoutVersion,this.measured,this.density,'display');
  }
  subscribeLayout(listener: FxLayoutListener): () => void {
    this.layoutListeners.push(listener);
    return () => {const i=this.layoutListeners.indexOf(listener);if(i>=0)this.layoutListeners.splice(i,1);};
  }
  private notifyLayout(): void {
    this.layoutVersion++;const listeners=this.layoutListeners.slice();
    for(let i=0;i<listeners.length;i++) {try{listeners[i](this.getGeometrySnapshot());}catch(_){if(this.controller!==undefined)this.controller.reportCallbackFailure();}}
  }
  async flushGeometry(): Promise<void> {if(this.fallback!==undefined && this.fallback.flushGeometry!==undefined)await this.fallback.flushGeometry();await this.frameCompletion;await this.layoutCompletion;await this.tail;this.assertAlive();}
  cancelTouch(reason: FxTouchCancelReason): void {
    if(this.view!==undefined && this.view.cancelTouch!==undefined)this.view.cancelTouch(reason);
    if(this.fallback!==undefined && this.fallback.cancelTouch!==undefined)this.fallback.cancelTouch(reason);
  }
  getProjection(): FxProjection {return this.projection;}
  async create(): Promise<void> {
    this.assertAlive();if(this.native!==undefined || this.fallbackCreated)return;
    if(this.fallback!==undefined){await this.createFallback();return;}
    try {
      await this.factory.checkAccess();this.assertAlive();this.native=await this.factory.create();this.assertAlive();
      if(this.native.subscribeVisibility!==undefined)this.releaseVisibility=this.native.subscribeVisibility((destroyed: boolean) => {
        this.cancelTouch(destroyed?FxTouchCancelReason.DESTROYED:FxTouchCancelReason.HIDDEN);this.cancelAnimations();
        if(destroyed) {if(this.controller!==undefined)this.controller.cancel().catch((error: Error) => this.reportError(error));else this.destroy().catch((error: Error) => this.reportError(error));}
        else {if(this.controller!==undefined)this.controller.nativeHidden();if(this.view!==undefined){if(this.view.nativeHidden!==undefined)this.view.nativeHidden();else this.observe(this.view.hide());}}
      });
      this.releaseNative=this.native.subscribe(() => {this.cancelTouch(FxTouchCancelReason.HOST_CHANGED);this.cancelAnimations();this.observe(this.move(this.position,false));});
      await this.native.load(this);await this.native.setBackground('#00000000');
      this.applySafeArea(this.input.config.safeAreaPolicy);
      await this.applyInteraction(this.input.config);
      await this.enqueueNative(async () => {await this.projectNative(initial(this.input));this.positioned=false;});
    } catch(error) {
      const cause=error as Error;await this.cleanupNative();
      if(!this.destroyed && this.fallbackFactory!==undefined && cause instanceof FxError && (cause.code==='PERMISSION_DENIED'||cause.code==='CAPABILITY_UNSUPPORTED')) {
        this.fallback=this.fallbackFactory();this.fallbackCause=cause as FxError;
        if(this.controller!==undefined && this.fallback.bindController!==undefined)this.fallback.bindController(this.controller);
        if(this.fallback.subscribeLifecycle!==undefined)this.releaseFallback=this.fallback.subscribeLifecycle((type: FxEventType) => this.lifecycle(type));
        if(this.fallback.subscribeLayout!==undefined)this.releaseFallbackLayout=this.fallback.subscribeLayout(() => this.notifyLayout());
        await this.createFallback();
        return;
      }
      throw cause as Error;
    }
  }
  private async createFallback(): Promise<void> {
    const fallback=this.fallback;if(fallback===undefined || this.fallbackCreated)return;
    // The app owns any ATTACH emitted synchronously inside its create, even before readiness.
    this.actualScope=FxScope.APP;
    await fallback.create();this.assertAlive();this.fallbackCreated=true;
    const cause=this.fallbackCause;this.fallbackCause=undefined;
    if(cause!==undefined) {
      const event: FxEvent={type:FxEventType.ERROR,position:this.getPosition(),actualScope:FxScope.APP,error:cause};
      if(this.onEvent!==undefined)this.onEvent(event);else if(this.controller!==undefined)this.controller.reportError(cause as Error);
    }
  }
  async applyConfig(config: FxConfig): Promise<void> {
    this.assertAlive();if(this.fallback!==undefined){await this.fallback.applyConfig(config);this.input.config=config.copy();return;}
    const next=config.copy();this.cancelTouch(FxTouchCancelReason.CONFIG_CHANGED);this.cancelAnimations();
    await this.enqueueNative(async () => {
      this.assertAlive();const previous=this.input.config;this.input.config=next;
      try {this.applySafeArea(next.safeAreaPolicy);await this.applyInteraction(next);await this.projectNative(this.positioned?clamp(this.position,bounds(this.input)):initial(this.input));if(this.view!==undefined)await this.view.applyConfig(next);}
      catch(error){this.input.config=previous;try{this.applySafeArea(previous.safeAreaPolicy);await this.applyInteraction(previous);}catch(_){}throw error as Error;}
    });
  }
  private applySafeArea(policy: FxSafeAreaPolicy): void {
    const native=this.requireNative();
    if(native.setSafeAreaPolicy!==undefined)native.setSafeAreaPolicy(policy);
    else if(policy!==FxSafeAreaPolicy.HOST)throw new FxError('CAPABILITY_UNSUPPORTED','Native adapter does not support explicit safe-area policy');
  }
  private async applyInteraction(config: FxConfig): Promise<void> {
    const touchable=!config.layoutOnly && (config.gestureMode===FxGestureMode.ANDROID_2 || config.displayMode!==FxDisplayMode.DisplayOnly);
    // Disable touch before restoring native focus; disable focus before enabling touch.
    if(!touchable)await this.requireNative().setTouchable(false);
    await this.applyFocus(config.focusPolicy);
    if(touchable)await this.requireNative().setTouchable(true);
  }
  private async applyFocus(policy: FxFocusPolicy): Promise<void> {
    const native=this.requireNative();
    if(native.setFocusPolicy!==undefined)await native.setFocusPolicy(policy);
    else if(policy!==FxFocusPolicy.DEFAULT)throw new FxError('CAPABILITY_UNSUPPORTED','Native adapter does not support explicit focus policy');
  }
  async show(): Promise<void> {this.assertAlive();if(this.fallback!==undefined)return this.fallback.show();if(this.view!==undefined)await this.view.show();try{await this.requireNative().show();}catch(error){if(this.view!==undefined)await this.view.hide();throw error as Error;}}
  async hide(): Promise<void> {this.cancelTouch(FxTouchCancelReason.HIDDEN);this.cancelAnimations();if(this.fallback!==undefined)return this.fallback.hide();if(this.native!==undefined){await this.native.hide();if(this.view!==undefined)await this.view.hide();}}
  async move(point: FxPoint, animate: boolean): Promise<FxPoint> {
    this.frameRevision++;this.initialMeasurementPending=false;this.pendingFrame=undefined;this.clock.cancel();return this.runMove(point,animate);
  }
  private async runMove(point: FxPoint, animate: boolean, dragging: boolean = false, frameRevision?: number): Promise<FxPoint> {
    this.assertAlive();if(this.fallback!==undefined)return this.fallback.move(point,animate);
    const token=this.animation.begin();const target=clamp(point,bounds(this.input,dragging));const start=this.getPosition();const startTime=this.clock.now();
    const duration=animate && this.input.config.animation.enabled ? this.input.config.animation.durationMs:0;
    do {
      if(!this.animation.isCurrent(token))return this.getPosition();
      const fraction=duration===0?1:Math.min(1,(this.clock.now()-startTime)/duration);
      const t=this.curve(fraction);await this.enqueueProjection({x:start.x+(target.x-start.x)*t,y:start.y+(target.y-start.y)*t},token,frameRevision);
      if(fraction===1 || !this.animation.isCurrent(token))break;await this.clock.wait();
    } while(this.animation.isCurrent(token));
    return this.getPosition();
  }
  /** Coalesce drag frames while one native transaction is in flight. Final settle uses awaited move. */
  moveFrame(point: FxPoint): void {
    this.frameRevision++;this.initialMeasurementPending=false;this.pendingFrame={x:point.x,y:point.y};if(this.frameRunning)return;this.frameRunning=true;
    this.frameCompletion=this.drainFrames().finally(() => {this.frameRunning=false;if(this.pendingFrame!==undefined && !this.destroyed)this.moveFrame(this.pendingFrame);});this.observe(this.frameCompletion);
  }
  private async drainFrames(): Promise<void> {while(this.pendingFrame!==undefined && !this.destroyed){const point=this.pendingFrame;this.pendingFrame=undefined;await this.runMove(point,false,true,this.frameRevision);}}
  cancelAnimations(): void {this.frameRevision++;this.animation.cancel();this.clock.cancel();this.pendingFrame=undefined;if(this.view!==undefined)this.view.cancelAnimations();if(this.fallback!==undefined && this.fallback.cancelAnimations!==undefined)this.fallback.cancelAnimations();}
  layoutContent(size: FxSize, applied: boolean = false): void {
    if(this.destroyed || size.width<=0 || size.height<=0)return;
    const changed=size.width!==this.input.content.width || size.height!==this.input.content.height;
    if(!changed && !applied)return;
    const next: FxSize={width:size.width,height:size.height};
    if(changed){if(this.input.config.boundaryMode!==FxBoundaryMode.ANDROID_2)this.cancelTouch(FxTouchCancelReason.LAYOUT_CHANGED);this.cancelAnimations();}
    this.layoutCompletion=this.enqueueNative(async () => {
      if(this.destroyed)return;const previous=this.input.content;this.input.content=next;
      try {
        const first=applied && !this.measured && this.initialMeasurementPending && this.input.config.boundaryMode===FxBoundaryMode.ANDROID_2;
        if(changed || first)await this.projectNative(first?initial(this.input):clamp(this.position,bounds(this.input)));
        if(applied)this.initialMeasurementPending=false;
        if(applied){this.measured=true;this.notifyLayout();}
      }catch(error){this.input.content=previous;throw error as Error;}
    });this.observe(this.layoutCompletion);
  }
  reportError(error: Error): void {if(this.controller!==undefined)this.controller.reportError(error);}
  async destroy(): Promise<void> {
    if(this.destroyed)return;this.destroyed=true;this.cancelTouch(FxTouchCancelReason.DESTROYED);this.cancelAnimations();
    try {if(this.fallback!==undefined)await this.fallback.destroy();else {await this.tail;await this.cleanupNative();}}
    finally {if(this.releaseFallbackLayout!==undefined)this.releaseFallbackLayout();this.releaseFallbackLayout=undefined;if(this.releaseFallback!==undefined)this.releaseFallback();this.releaseFallback=undefined;this.controller=undefined;this.listeners=[];this.layoutListeners=[];this.fallback=undefined;}
  }
  private enqueueProjection(point: FxPoint, token: number, frameRevision?: number): Promise<void> {
    return this.enqueueNative(async () => {if(!this.destroyed && this.animation.isCurrent(token) && (frameRevision===undefined || frameRevision===this.frameRevision))await this.projectNative(point,token,frameRevision);});
  }
  private enqueueNative(operation: () => Promise<void>): Promise<void> {
    const run=this.tail.then(operation);this.tail=run.then(()=>{},()=>{});return run;
  }
  private async projectNative(point: FxPoint, token?: number, frameRevision?: number): Promise<void> {
    const native=this.requireNative();const viewport=native.getViewport();if(!Number.isFinite(viewport.density)||viewport.density<=0)throw new FxError('INVALID_GEOMETRY','Invalid target display density');
    const oldViewport=this.input.viewport;const oldLimits=bounds(this.input);const edge=logicalEdge(point,this.input);
    this.input.viewport={size:{width:viewport.size.width,height:viewport.size.height},insets:{left:viewport.insets.left,top:viewport.insets.top,right:viewport.insets.right,bottom:viewport.insets.bottom}};
    const changed=oldViewport.size.width!==viewport.size.width || oldViewport.size.height!==viewport.size.height ||
      oldViewport.insets.left!==viewport.insets.left || oldViewport.insets.top!==viewport.insets.top ||
      oldViewport.insets.right!==viewport.insets.right || oldViewport.insets.bottom!==viewport.insets.bottom || this.density!==viewport.density;
    const logical=this.input.config.boundaryMode===FxBoundaryMode.ANDROID_2 && !changed ? {x:point.x,y:point.y} :
      (this.positioned ? (this.input.config.boundaryMode===FxBoundaryMode.ANDROID_2?resizePosition(point,oldViewport.size,this.input.content,this.input):remap(point,oldLimits,edge,bounds(this.input))) : initial(this.input));
    this.requestedPosition={x:logical.x,y:logical.y};
    const projection=project(logical,this.input);const d=viewport.density;
    const size: FxSize={width:Math.round(projection.visibleSize.width*d),height:Math.round(projection.visibleSize.height*d)};
    if(size.width<=0 || size.height<=0)throw new FxError('CAPABILITY_UNSUPPORTED','Native window requires a positive visible slice');
    const previous=native.getRect();
    try {
      await native.resize(size);
      const x=projection.position.x*d;const y=projection.position.y*d;
      let actual=await native.movePx(this.input.config.gestureMode===FxGestureMode.ANDROID_2 ?
        {x:Math.trunc(x),y:Math.trunc(y)}:{x:Math.round(x),y:Math.round(y)});
      if((actual.width<=0 || actual.height<=0) && native.prepareGeometry!==undefined) {
        await native.prepareGeometry();actual=native.getRect();
      }
      if(this.destroyed || token!==undefined && !this.animation.isCurrent(token)) {
        if(previous.width>0 && previous.height>0) {await native.resize({width:previous.width,height:previous.height});await native.movePx({x:previous.x,y:previous.y});}this.input.viewport=oldViewport;return;
      }
      if(actual.width!==size.width||actual.height!==size.height)throw new FxError('CAPABILITY_UNSUPPORTED','Native window cannot represent requested visible slice');
      this.position={x:logical.x+(actual.x/d-projection.position.x),y:logical.y+(actual.y/d-projection.position.y)};
      this.positioned=true;this.projection={position:{x:actual.x/d,y:actual.y/d},visibleSize:projection.visibleSize,contentOffset:projection.contentOffset};
      this.density=d;
      // Keep native readback authoritative without rewinding a newer logical finger frame.
      if(this.view!==undefined && (frameRevision===undefined || frameRevision===this.frameRevision))this.view.adoptPosition(this.position);
      if(changed)this.notifyLayout();
    } catch(error) {
      this.input.viewport=oldViewport;
      if(this.cancelIfTerminated(native))throw error as Error;
      // Restore the actual native rectangle; keep the last successful logical projection.
      try {if(previous.width>0 && previous.height>0) {await native.resize({width:previous.width,height:previous.height});await native.movePx({x:previous.x,y:previous.y});}}catch(rollback){this.cancelIfTerminated(native);throw rollback as Error;}
      throw error as Error;
    }
  }
  private cancelIfTerminated(native: FxNativeWindow): boolean {
    if(native.terminated!==true)return false;
    // Mark public state terminal now; queued cleanup must not be awaited inside its own transaction.
    if(this.controller!==undefined)this.controller.cancel().catch((failure: Error) => this.reportError(failure));
    else this.destroy().catch((failure: Error) => this.reportError(failure));
    return true;
  }
  private async cleanupNative(): Promise<void> {
    let failure: Error | undefined;
    try{if(this.releaseVisibility!==undefined)this.releaseVisibility();}catch(error){failure=error as Error;}this.releaseVisibility=undefined;
    const native=this.native;this.native=undefined;const view=this.view;this.view=undefined;
    try {if(native!==undefined)await native.destroy();}
    finally {try{if(view!==undefined)await view.destroy();}finally{if(this.releaseNative!==undefined)this.releaseNative();this.releaseNative=undefined;if(native!==undefined)this.lifecycle(FxEventType.DETACH);}}
    if(failure!==undefined)throw failure;
  }
  private curve(t: number): number {switch(this.input.config.animation.curve){case FxAnimationCurve.LINEAR:return t;case FxAnimationCurve.EASE_IN:return t*t;case FxAnimationCurve.EASE_OUT:return 1-(1-t)*(1-t);default:return t*t*(3-2*t);}}
  private requireNative(): FxNativeWindow {if(this.native===undefined)throw new FxError('NO_HOST','System window is not created');return this.native;}
  private assertAlive(): void {if(this.destroyed)throw new FxError('DESTROYED','System platform is destroyed');}
  private lifecycle(type: FxEventType): void {for(let i=0;i<this.listeners.length;i++)this.listeners[i](type);}
  private observe(promise: Promise<void> | Promise<FxPoint>): void {promise.catch((error: Error) => this.reportError(error));}
}
