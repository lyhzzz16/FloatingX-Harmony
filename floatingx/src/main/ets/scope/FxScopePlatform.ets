import { UIContext } from '@ohos.arkui.UIContext';
import { Content } from '@ohos.arkui.node';
import { FxPlatform, FxScope, FxEventType } from '../core/FxPlatform';
import { FxController } from '../core/FxController';
import { FxConfig } from '../core/FxConfig';
import { FxError } from '../core/FxError';
import { FxPoint, FxSize, FxInsets, FxViewport, FxProjection, FxDisplayMode, FxAnimationCurve, FxBoundaryMode, FxGeometrySnapshot, FxLayoutListener, FxTouchPhase, FxTouchSnapshot, FxTouchCancelReason, FxReleaseDecision } from '../core/FxTypes';
import { FxGeometryInput, initial, clamp, bounds, settle, project, logicalEdge, remap, snapshot } from '../geometry/FxGeometry';
import { FxContentSource, FxContentMount } from '../component/FxContent';
import { FxTouch, FxPointer, FxTouchResult } from '../component/FxTouch';
import { FxAnimation } from '../component/FxAnimation';

export interface FxScopeBoundary {
  displayPointers: boolean;
  cancelPending?(): void;
  flush?(): Promise<void>;
  move(point: FxPoint, animate: boolean): Promise<FxPoint>;
  moveFrame(point: FxPoint): void;
}
export interface FxDragArea { x: number; y: number; width: number; height: number; }
export interface FxInteractions {
  /** Observes a primary pointer in absolute vp; no return value changes input dispatch. */
  onTouch?: (event: FxTouchSnapshot) => void | Promise<void>;
  /** Synchronous release decision before settling/saving. CONSUMED also suppresses this surface's click. */
  onRelease?: (event: FxTouchSnapshot) => FxReleaseDecision;
  dragArea?: FxDragArea;
  onClick?: () => void | Promise<void>;
  onLongPress?: () => void | Promise<void>;
  onDrag?: (position: FxPoint) => void | Promise<void>;
}
export class FxScopeSnapshot {
  content?: Content;
  visible: boolean = false;
  opacity: number = 1;
  config: FxConfig = new FxConfig();
  projection: FxProjection = { position:{x:0,y:0}, visibleSize:{width:1,height:1}, contentOffset:{x:0,y:0} };
  size: FxSize = {width:1,height:1};
}
/** Local adapter owns no global window. Coordinates refer to the measured host content area. */
export class FxScopePlatform implements FxPlatform {
  readonly actualScope: FxScope = FxScope.SCOPE;
  private controller?: FxController;
  private managesHostVisibility: boolean = true;
  private source?: FxContentSource;
  private mount?: FxContentMount;
  private context?: UIContext;
  private created: boolean = false;
  private attached: boolean = false;
  private destroyed: boolean = false;
  private positioned: boolean = false;
  private hostReady: boolean = false;
  private snapshot: FxScopeSnapshot = new FxScopeSnapshot();
  private position: FxPoint = {x:0,y:0};
  private viewport: FxViewport = {size:{width:1,height:1},insets:{left:0,top:0,right:0,bottom:0}};
  private listeners: (() => void)[] = [];
  private lifecycleListeners: ((type: FxEventType) => void)[] = [];
  private animation: FxAnimation = new FxAnimation();
  private finishAnimation?: () => void;
  private interactionGeneration: number = 0;
  private touch: FxTouch = new FxTouch('Normal',8,300,500);
  private primary?: FxPointer;
  private downPointer?: FxPointer;
  private downPosition: FxPoint = {x:0,y:0};
  private layoutVersion: number = 0;
  private measured: boolean = false;
  private layoutListeners: FxLayoutListener[] = [];
  private dragged: boolean = false;
  private longPressTimer: number = -1;
  interactions: FxInteractions;
  private boundary?: FxScopeBoundary;
  constructor(interactions: FxInteractions = {}, boundary?: FxScopeBoundary) { this.interactions=interactions;this.boundary=boundary; }
  adoptPosition(point: FxPoint): void { this.position={x:point.x,y:point.y};this.positioned=true;this.refresh(); }
  bindController(controller: FxController, managesHostVisibility: boolean = true): void { this.controller = controller; this.managesHostVisibility=managesHostVisibility; }
  getSnapshot(): FxScopeSnapshot { return this.snapshot; }
  getGeometry(): FxGeometryInput { return {viewport:this.viewport,content:this.snapshot.size,config:this.snapshot.config}; }
  getGeometrySnapshot(): FxGeometrySnapshot {
    return snapshot(this.getGeometry(),this.position,this.snapshot.projection,this.position,
      this.layoutVersion,this.measured,this.context===undefined ? 1:this.context.vp2px(1),'host');
  }
  subscribeLayout(listener: FxLayoutListener): () => void {
    this.layoutListeners.push(listener);
    return () => {const i=this.layoutListeners.indexOf(listener);if(i>=0)this.layoutListeners.splice(i,1);};
  }
  private notifyLayout(): void {
    this.layoutVersion++;
    const listeners=this.layoutListeners.slice();
    for(let i=0;i<listeners.length;i++) this.runCallback(() => listeners[i](this.getGeometrySnapshot()));
  }
  getPosition(): FxPoint { return {x:this.position.x,y:this.position.y}; }
  isHostVisible(): boolean { return this.context !== undefined && this.hostReady; }
  subscribe(listener: () => void): () => void {
    this.listeners.push(listener);
    return () => { const i=this.listeners.indexOf(listener); if(i>=0) this.listeners.splice(i,1); };
  }
  subscribeLifecycle(listener: (type: FxEventType) => void): () => void {
    this.lifecycleListeners.push(listener);
    return () => { const i=this.lifecycleListeners.indexOf(listener); if(i>=0) this.lifecycleListeners.splice(i,1); };
  }
  mountHost(context: UIContext, source: FxContentSource): void {
    if(this.destroyed) return;
    if(this.context !== undefined) throw new FxError('INVALID_CONFIG','Scope adapter already has a host');
    this.context=context; this.source=source; this.snapshot.size={width:source.size.width,height:source.size.height};
    this.hostReady=false;
    // Wait for positive measured layout before restoring or showing.
  }
  layoutHost(size: FxSize, insets: FxInsets = {left:0,top:0,right:0,bottom:0}): void {
    if(this.destroyed || size.width<=0 || size.height<=0) return;
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.LAYOUT_CHANGED);
    const previous=bounds(this.getGeometry()); const edge=logicalEdge(this.position,this.getGeometry());
    const remapPosition=this.positioned && this.hostReady;
    this.viewport.size={width:size.width,height:size.height};
    this.viewport.insets={left:insets.left,top:insets.top,right:insets.right,bottom:insets.bottom};
    this.hostReady=true;
    if(this.created) this.attachContent();
    if(this.positioned) this.position=remapPosition ? remap(this.position,previous,edge,bounds(this.getGeometry())) : clamp(this.position,bounds(this.getGeometry()));
    this.refresh(); this.notifyLayout();
    if(this.controller !== undefined && this.managesHostVisibility) this.controller.setHostVisible(true).catch(() => {});
  }
  layoutContent(size: FxSize, applied: boolean = false): void {
    if(this.destroyed)return;
    if(this.mount!==undefined && this.mount.measure!==undefined) {
      const full=this.mount.measure();if(full===undefined)return;size=full;
    }
    if(size.width<=0 || size.height<=0) return;
    if(applied) this.measured=true;
    if(size.width===this.snapshot.size.width && size.height===this.snapshot.size.height) {
      if(applied)this.notifyLayout(); return;
    }
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.LAYOUT_CHANGED); this.snapshot.size={width:size.width,height:size.height};
    if(this.positioned) this.position=clamp(this.position,bounds(this.getGeometry())); this.refresh();
    if(applied)this.notifyLayout();
  }
  unmountHost(): void {
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.HOST_CHANGED); this.snapshot.visible=false; this.measured=false;
    this.context=undefined; this.hostReady=false;
    if(this.attached) { this.attached=false; this.lifecycle(FxEventType.DETACH); }
    if(this.controller !== undefined && this.managesHostVisibility) this.controller.setHostVisible(false).catch(() => {});
    try { this.releaseContent(); }
    catch(error) { if(this.controller!==undefined) this.controller.reportError(error as Error); }
    finally { this.source=undefined; this.refresh(); }
  }
  async create(): Promise<void> {
    this.assertAlive();
    if(this.context===undefined) throw new FxError('NO_HOST','Scope host is not mounted');
    this.created=true; this.attachContent();
  }
  async applyConfig(config: FxConfig): Promise<void> {
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.CONFIG_CHANGED); this.snapshot.config=config.copy();
    this.touch=new FxTouch(config.displayMode,8,config.clickIntervalMs,500);
    this.position=this.positioned ? clamp(this.position,bounds(this.getGeometry())) : initial(this.getGeometry());
    this.positioned=true; this.refresh();
  }
  async show(): Promise<void> {
    this.assertAlive(); if(this.context===undefined) return;
    this.snapshot.visible=true; this.snapshot.opacity=this.snapshot.config.animation.enabled ? 0:1; this.refresh();
    await this.animate(() => { this.snapshot.opacity=1; this.refresh(); },this.snapshot.config.animation.enabled);
  }
  async hide(beforeHidden?: () => void): Promise<void> {
    const visible=this.snapshot.visible; const opacity=this.snapshot.opacity;
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.HIDDEN);
    await this.animate(() => { this.snapshot.opacity=0; this.refresh(); },this.snapshot.config.animation.enabled);
    try { if(beforeHidden!==undefined) beforeHidden(); }
    catch(error) { this.snapshot.visible=visible; this.snapshot.opacity=opacity; this.refresh(); throw error as Error; }
    this.snapshot.visible=false; this.refresh();
  }
  async move(point: FxPoint, animate: boolean): Promise<FxPoint> {
    this.assertAlive(); const target=clamp(point,bounds(this.getGeometry()));
    if(this.boundary!==undefined) {const actual=await this.boundary.move(target,animate);this.adoptPosition(actual);return this.getPosition();}
    await this.animate(() => { this.position=target; this.positioned=true; this.refresh(); },animate);
    return this.getPosition();
  }
  async destroy(): Promise<void> {
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.DESTROYED); this.snapshot.visible=false;
    if(this.attached) { this.attached=false; this.lifecycle(FxEventType.DETACH); }
    try { this.releaseContent(); }
    finally {
      this.created=false; this.destroyed=true; this.context=undefined; this.hostReady=false; this.source=undefined;
      this.refresh(); this.listeners=[]; this.lifecycleListeners=[]; this.layoutListeners=[]; this.controller=undefined;
    }
  }
  cancelAnimations(): void {
    this.interactionGeneration++;
    this.animation.cancel();
    const finish=this.finishAnimation; this.finishAnimation=undefined; if(finish!==undefined) finish();
  }
  hasPrimaryPointer(): boolean {return this.primary!==undefined;}
  handleTouch(event: TouchEvent): void {
    if(this.destroyed || this.context===undefined || !this.snapshot.visible || this.snapshot.config.displayMode===FxDisplayMode.DisplayOnly) return;
    if(event.type===TouchType.Cancel) {
      const released=this.touchSnapshot(FxTouchPhase.CANCEL,FxTouchCancelReason.SYSTEM);
      const wasDragged=this.dragged;
      this.resetTouch();
      if(released!==undefined)this.finishTouch(released,wasDragged);
      return;
    }
    const changes=event.changedTouches;
    for(let i=0;i<changes.length;i++) {
      const native=changes[i];
      const pointer: FxPointer={id:native.id,x:this.boundary!==undefined && this.boundary.displayPointers?native.displayX:native.windowX,y:this.boundary!==undefined && this.boundary.displayPointers?native.displayY:native.windowY,timeMs:event.timestamp/1000000};
      if(event.type===TouchType.Down) {
        if(this.primary!==undefined) continue;
        this.cancelAnimations(); this.primary=pointer; this.downPointer=pointer; this.downPosition=this.getPosition(); this.dragged=false;
        this.touch.down(pointer,this.position);
        this.longPressTimer=setTimeout(() => {
          if(this.primary===undefined) return;
          const current=this.primary;
          this.deliver(this.touch.move({id:current.id,x:current.x,y:current.y,timeMs:pointer.timeMs+500}));
        },500);
        this.observeTouch(this.touchSnapshot(FxTouchPhase.DOWN));
      } else if(this.primary!==undefined && pointer.id===this.primary.id) {
        this.primary=pointer;
        if(event.type===TouchType.Move) {
          this.deliver(this.touch.move(pointer));
          this.observeTouch(this.touchSnapshot(FxTouchPhase.MOVE));
        } else if(event.type===TouchType.Up) {
          const result=this.touch.up(pointer);
          if(result.kind==='end' && (result.position.x!==this.position.x || result.position.y!==this.position.y)) {
            this.position=this.dragPosition(result.position); this.dragged=true; this.refresh();
            if(this.boundary!==undefined)this.boundary.moveFrame(this.position);
          }
          const released=this.touchSnapshot(FxTouchPhase.UP);
          const wasDragged=this.dragged;
          this.resetTouch();
          if(released!==undefined)this.finishTouch(released,wasDragged,result);
        }
      }
    }
  }
  /** Terminates the primary pointer once; lifecycle cancellation never settles or clicks. */
  cancelTouch(reason: FxTouchCancelReason = FxTouchCancelReason.HOST_CHANGED): void {
    const event=this.touchSnapshot(FxTouchPhase.CANCEL,reason);
    this.resetTouch(); this.observeTouch(event);
  }
  private resetTouch(): void {
    this.touch.cancel(); this.primary=undefined; this.downPointer=undefined;
    clearTimeout(this.longPressTimer); this.longPressTimer=-1; this.dragged=false;
  }
  private touchSnapshot(phase: FxTouchPhase, reason?: FxTouchCancelReason): FxTouchSnapshot | undefined {
    const start=this.downPointer; const pointer=this.primary;
    if(start===undefined || pointer===undefined)return undefined;
    return {phase:phase,pointerId:start.id,startPointer:{x:start.x,y:start.y},pointer:{x:pointer.x,y:pointer.y},
      delta:{x:pointer.x-start.x,y:pointer.y-start.y},startPosition:{x:this.downPosition.x,y:this.downPosition.y},
      position:this.getPosition(),dragged:this.dragged,cancelReason:reason};
  }
  private observeTouch(event?: FxTouchSnapshot): void {
    const callback=this.interactions.onTouch;
    if(event!==undefined && callback!==undefined)this.runCallback(() => callback(this.copyTouch(event)));
  }
  private copyTouch(event: FxTouchSnapshot): FxTouchSnapshot {
    return {phase:event.phase,pointerId:event.pointerId,startPointer:{x:event.startPointer.x,y:event.startPointer.y},
      pointer:{x:event.pointer.x,y:event.pointer.y},delta:{x:event.delta.x,y:event.delta.y},
      startPosition:{x:event.startPosition.x,y:event.startPosition.y},position:{x:event.position.x,y:event.position.y},
      dragged:event.dragged,cancelReason:event.cancelReason};
  }
  private finishTouch(event: FxTouchSnapshot, wasDragged: boolean, result?: FxTouchResult): void {
    const generation=this.interactionGeneration;
    this.observeTouch(event);
    if(generation!==this.interactionGeneration || this.destroyed)return;
    let consumed=false;
    const callback=this.interactions.onRelease;
    if(callback!==undefined) {
      try {consumed=callback(this.copyTouch(event))===FxReleaseDecision.CONSUMED;}
      catch(_) {if(this.controller!==undefined)this.controller.reportCallbackFailure();}
    }
    if(consumed) {
      if(generation===this.interactionGeneration) {
        this.cancelAnimations();
        if(this.boundary!==undefined && this.boundary.cancelPending!==undefined)this.boundary.cancelPending();
      }
      return;
    }
    if(generation!==this.interactionGeneration || this.destroyed)return;
    // Release callbacks precede click, as in Android's touchCancel -> onUp -> performClickAction.
    if(result!==undefined)this.deliver(result);
    if(generation===this.interactionGeneration && wasDragged)this.settleDrag();
  }
  private dragPosition(point: FxPoint): FxPoint {
    return this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 ? clamp(point,bounds(this.getGeometry(),true)):point;
  }
  private deliver(result: FxTouchResult): void {
    try {
      if(result.kind==='drag') {
        this.dragged=true; clearTimeout(this.longPressTimer); this.position=this.dragPosition(result.position); this.refresh();
        if(this.boundary!==undefined)this.boundary.moveFrame(this.position);
        if(this.interactions.onDrag!==undefined) {
          const callback=this.interactions.onDrag; this.runCallback(() => callback(this.getPosition()));
        }
      } else if(result.kind==='click' && this.interactions.onClick!==undefined) this.runCallback(this.interactions.onClick);
      else if(result.kind==='longPress' && this.interactions.onLongPress!==undefined) this.runCallback(this.interactions.onLongPress);
    } catch(error) { if(this.controller!==undefined) this.controller.reportError(error as Error); }
  }
  private runCallback(callback: () => void | Promise<void>): void {
    try {
      const result=callback();
      if(result!==undefined) (result as Promise<void>).catch(() => {if(this.controller!==undefined)this.controller.reportCallbackFailure();});
    } catch(_) {if(this.controller!==undefined)this.controller.reportCallbackFailure();}
  }
  private settleDrag(): void {
    const target=settle(this.position,this.getGeometry());
    const generation=this.controller===undefined ? -1:this.controller.getGeneration();
    const noSettle=this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 && !this.snapshot.config.adsorb;
    const completed=noSettle ? (this.boundary!==undefined && this.boundary.flush!==undefined ? this.boundary.flush():Promise.resolve()) :
      this.move(target,this.snapshot.config.animation.enabled && this.snapshot.config.rebound);
    const interaction=this.interactionGeneration;
    this.observe(completed.then(async () => {
      if(this.controller!==undefined && this.controller.getGeneration()===generation && this.context!==undefined && this.interactionGeneration===interaction) await this.controller.savePosition();
    }));
  }
  private animate(change: () => void, enabled: boolean): Promise<void> {
    this.cancelAnimations(); const token=this.animation.begin(); const context=this.context;
    if(!enabled || context===undefined || this.snapshot.config.animation.durationMs===0) { change(); return Promise.resolve(); }
    return new Promise<void>((resolve) => {
      this.finishAnimation=resolve;
      const curve=this.snapshot.config.animation.curve;
      let nativeCurve=Curve.Ease;
      if(curve===FxAnimationCurve.LINEAR) nativeCurve=Curve.Linear;
      else if(curve===FxAnimationCurve.EASE_IN) nativeCurve=Curve.EaseIn;
      else if(curve===FxAnimationCurve.EASE_OUT) nativeCurve=Curve.EaseOut;
      else if(curve===FxAnimationCurve.EASE_IN_OUT) nativeCurve=Curve.EaseInOut;
      context.animateTo({duration:this.snapshot.config.animation.durationMs,curve:nativeCurve,onFinish:() => {
        if(!this.animation.isCurrent(token)) return;
        this.finishAnimation=undefined; resolve();
      }},() => { if(this.animation.isCurrent(token)) change(); });
    });
  }
  private attachContent(): void {
    if(this.mount!==undefined || this.context===undefined || this.source===undefined) return;
    this.mount=this.source.create(this.context);const mount=this.mount;
    if(mount.observeSize!==undefined)mount.observeSize((size: FxSize) => {if(this.mount===mount)this.layoutContent(size);});
    if(mount.observeLayout!==undefined)mount.observeLayout((size: FxSize) => {if(this.mount===mount)this.layoutContent(size,true);});
    this.snapshot.content=this.mount.content; this.attached=true;
    this.refresh(); this.lifecycle(FxEventType.ATTACH);
  }
  private releaseContent(): void {
    const mount=this.mount; this.mount=undefined; this.snapshot.content=undefined;
    if(mount!==undefined) mount.dispose();
  }
  private refresh(): void {
    if(this.positioned) this.snapshot.projection=project(this.position,this.getGeometry());
    for(let i=0;i<this.listeners.length;i++) this.listeners[i]();
  }
  private lifecycle(type: FxEventType): void { for(let i=0;i<this.lifecycleListeners.length;i++) this.lifecycleListeners[i](type); }
  private observe(result: Promise<void>): void { result.catch((error: Error) => { if(this.controller!==undefined) this.controller.reportError(error); }); }
  private assertAlive(): void { if(this.destroyed) throw new FxError('DESTROYED','Scope platform is destroyed'); }
}
