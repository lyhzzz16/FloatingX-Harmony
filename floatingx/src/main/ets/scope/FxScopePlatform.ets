import deviceInfo from '@ohos.deviceInfo';
import { UIContext } from '@ohos.arkui.UIContext';
import { Content } from '@ohos.arkui.node';
import { FxPlatform, FxScope, FxEventType } from '../core/FxPlatform';
import { FxController } from '../core/FxController';
import { FxConfig } from '../core/FxConfig';
import { FxError } from '../core/FxError';
import { FxPoint, FxSize, FxInsets, FxViewport, FxProjection, FxDisplayMode, FxAnimationCurve, FxBoundaryMode, FxGeometrySnapshot, FxLayoutListener, FxTouchPhase, FxTouchSnapshot, FxTouchCancelReason, FxReleaseDecision, FxGestureMode, FxSafeAreaPolicy } from '../core/FxTypes';
import { FxGeometryInput, initial, clamp, bounds, settle, project, logicalEdge, remap, snapshot, resizePosition } from '../geometry/FxGeometry';
import { FxContentSource, FxContentMount } from '../component/FxContent';
import { FxTouch, FxPointer, FxTouchResult, FxTouchClock, FxWallTouchClock } from '../component/FxTouch';
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
  /** Android helper initialization, once per selected pointer; observer DOWN is separate. */
  onDown?: (event: FxTouchSnapshot) => void | Promise<void>;
  /** Observes a primary pointer in absolute vp; no return value changes input dispatch. */
  onTouch?: (event: FxTouchSnapshot) => void | Promise<void>;
  /** Synchronous release decision before settling/saving. CONSUMED also suppresses this surface's click. */
  onRelease?: (event: FxTouchSnapshot) => FxReleaseDecision;
  /** Parent terminal notification after default settlement starts, before library click. */
  onUp?: (event: FxTouchSnapshot) => void | Promise<void>;
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
  private initialMeasurementPending: boolean = false;
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
  private nativeOwned: boolean = false;
  private panStartTime?: number;
  private activePointerIds: number[] = [];
  private parentTerminal?: FxTouchSnapshot;
  private touchClock: FxTouchClock;
  private pendingTap?: FxTouchSnapshot;
  private pendingTapResult?: FxTouchResult;
  private pendingTapGeneration: number = -1;
  private longPressTimer: number = -1;
  interactions: FxInteractions;
  private boundary?: FxScopeBoundary;
  constructor(interactions: FxInteractions = {}, boundary?: FxScopeBoundary, touchClock: FxTouchClock = new FxWallTouchClock()) { this.interactions=interactions;this.boundary=boundary;this.touchClock=touchClock; }
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
    const oldSize=this.viewport.size;
    const previous=bounds(this.getGeometry()); const edge=logicalEdge(this.position,this.getGeometry());
    const remapPosition=this.positioned && this.hostReady;
    this.viewport.size={width:size.width,height:size.height};
    this.viewport.insets={left:insets.left,top:insets.top,right:insets.right,bottom:insets.bottom};
    this.hostReady=true;
    if(this.created) this.attachContent();
    if(this.positioned) this.position=remapPosition ? (this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 ? resizePosition(this.position,oldSize,this.snapshot.size,this.getGeometry()):remap(this.position,previous,edge,bounds(this.getGeometry()))) : clamp(this.position,bounds(this.getGeometry()));
    this.refresh(); this.notifyLayout();
    if(this.controller !== undefined && this.managesHostVisibility) this.controller.setHostVisible(true).catch(() => {});
  }
  layoutContent(size: FxSize, applied: boolean = false): void {
    if(this.destroyed)return;
    if(this.mount!==undefined && this.mount.measure!==undefined) {
      const full=this.mount.measure();if(full===undefined)return;size=full;
    }
    if(size.width<=0 || size.height<=0) return;
    const firstMeasurement=applied && !this.measured;
    if(applied) this.measured=true;
    if(size.width===this.snapshot.size.width && size.height===this.snapshot.size.height) {
      if(firstMeasurement && this.initialMeasurementPending && this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 && !this.primary) {this.position=initial(this.getGeometry());this.refresh();}
      if(applied){this.initialMeasurementPending=false;this.notifyLayout();} return;
    }
    this.cancelAnimations();
    if(this.snapshot.config.boundaryMode!==FxBoundaryMode.ANDROID_2)this.cancelTouch(FxTouchCancelReason.LAYOUT_CHANGED);
    this.snapshot.size={width:size.width,height:size.height};
    if(this.positioned) this.position=firstMeasurement && this.initialMeasurementPending && this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 && !this.primary ? initial(this.getGeometry()):clamp(this.position,bounds(this.getGeometry())); this.refresh();
    if(applied){this.initialMeasurementPending=false;this.notifyLayout();}
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
    if(this.managesHostVisibility && this.boundary===undefined && config.safeAreaPolicy!==FxSafeAreaPolicy.HOST)
      throw new FxError('CAPABILITY_UNSUPPORTED','A local Scope uses its measured host; explicit system avoid regions require App or System with a WindowHost');
    if(config.gestureMode===FxGestureMode.ANDROID_2) {
      if(deviceInfo.sdkApiVersion<20)throw new FxError('CAPABILITY_UNSUPPORTED','Whole-content child touch cancellation requires API 20');
      if(this.interactions.dragArea!==undefined)throw new FxError('INVALID_CONFIG','ANDROID_2 uses whole-content arbitration; dragArea is a legacy surface option');
    }
    const resolved=config.copy();
    if(resolved.gestureMode===FxGestureMode.ANDROID_2 && resolved.touchSlopVp===undefined) {
      const context=this.context;
      if(context===undefined)throw new FxError('NO_HOST','Gesture configuration requires a mounted UIContext');
      let distance=Number.NaN;
      context.runScopedTask(() => { distance=new PanGestureOptions().getDistance(); });
      if(!Number.isFinite(distance) || distance<=0)throw new FxError('CAPABILITY_UNSUPPORTED','ArkUI did not provide a positive Pan distance');
      resolved.touchSlopVp=distance;
    }
    this.cancelAnimations(); this.cancelTouch(FxTouchCancelReason.CONFIG_CHANGED); this.snapshot.config=resolved;
    this.touch=new FxTouch(resolved.displayMode,resolved.touchSlopVp===undefined?8:resolved.touchSlopVp,resolved.clickIntervalMs,500,resolved.gestureMode,this.touchClock);
    this.initialMeasurementPending=!this.positioned && !this.measured;
    this.position=this.positioned ? clamp(this.position,bounds(this.getGeometry())) : initial(this.getGeometry());
    this.positioned=true; this.refresh();
  }
  async show(): Promise<void> {
    this.assertAlive(); if(this.context===undefined) return;
    this.snapshot.visible=true; this.snapshot.opacity=this.snapshot.config.animation.enabled ? 0:1; this.refresh();
    await this.animate(() => { this.snapshot.opacity=1; this.refresh(); },this.snapshot.config.animation.enabled);
  }
  nativeHidden(): void {
    this.cancelAnimations();this.cancelTouch(FxTouchCancelReason.HIDDEN);
    this.snapshot.visible=false;this.snapshot.opacity=0;this.refresh();
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
    this.initialMeasurementPending=false;
    this.assertAlive(); const target=clamp(point,bounds(this.getGeometry()));
    if(this.boundary!==undefined) {this.cancelAnimations();const generation=this.interactionGeneration;const actual=await this.boundary.move(target,animate);if(generation===this.interactionGeneration)this.adoptPosition(actual);return this.getPosition();}
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
  canStartPan(event: BaseGestureEvent): boolean {
    if(this.primary===undefined || this.activePointerIds[0]!==this.primary.id)return false;
    for(let i=0;i<event.fingerList.length;i++) {
      const finger=event.fingerList[i];if(finger.id!==this.primary.id)continue;
      return this.touch.shouldIntercept({id:finger.id,x:this.boundary?.displayPointers?finger.displayX:finger.globalX,
        y:this.boundary?.displayPointers?finger.displayY:finger.globalY,timeMs:0});
    }
    return false;
  }
  /** Native recognizers arbitrate ownership; raw DOWN remains observable before child dispatch. */
  handlePan(event: GestureEvent, starting: boolean = false): void {
    if(this.primary===undefined || !this.snapshot.visible || this.snapshot.config.layoutOnly || this.snapshot.config.displayMode!==FxDisplayMode.Normal)return;
    if(starting) {
      this.nativeOwned=true;this.panStartTime=event.timestamp;return;
    }
    if(this.panStartTime!==undefined && event.timestamp===this.panStartTime)return;
    if(this.activePointerIds.length>0 && this.activePointerIds[0]!==this.primary.id)return;
    for(let i=0;i<event.fingerList.length;i++) {
      const finger=event.fingerList[i];if(finger.id!==this.primary.id)continue;
      this.nativeOwned=true;
      this.primary={id:finger.id,x:this.boundary?.displayPointers?finger.displayX:finger.globalX,
        y:this.boundary?.displayPointers?finger.displayY:finger.globalY,timeMs:event.timestamp/1000000};
      this.deliver(this.touch.move(this.primary));break;
    }
  }
  completeSurfaceTap(): void {
    if(this.boundary?.displayPointers)return;
    const generation=this.interactionGeneration;
    Promise.resolve().then(() => {
      const event=this.pendingTap;const result=this.pendingTapResult;
      this.pendingTap=undefined;this.pendingTapResult=undefined;
      if(event===undefined || generation!==this.pendingTapGeneration || generation!==this.interactionGeneration)return;
      this.finishTouch(event,false,result,false);
    });
  }
  handleTouch(event: TouchEvent, observeOnly: boolean = false): void {
    if(this.destroyed || this.context===undefined || !this.snapshot.visible || this.snapshot.config.layoutOnly || this.snapshot.config.displayMode===FxDisplayMode.DisplayOnly) return;
    if(this.snapshot.config.gestureMode===FxGestureMode.ANDROID_2){this.handleAndroidTouch(event,observeOnly);return;}
    if(event.type===TouchType.Cancel) {
      const released=this.touchSnapshot(FxTouchPhase.CANCEL,FxTouchCancelReason.SYSTEM);
      const wasDragged=this.dragged;
      this.resetTouch();
      if(released!==undefined) {if(observeOnly && !wasDragged)this.observeTouch(released);else this.finishTouch(released,wasDragged);}
      return;
    }
    const changes=event.changedTouches;
    for(let i=0;i<changes.length;i++) {
      const native=changes[i];
      const pointer: FxPointer={id:native.id,x:this.boundary!==undefined && this.boundary.displayPointers?native.displayX:native.windowX,y:this.boundary!==undefined && this.boundary.displayPointers?native.displayY:native.windowY,timeMs:event.timestamp/1000000};
      if(event.type===TouchType.Down) {
        if(this.primary!==undefined) continue;
        this.pendingTap=undefined;this.pendingTapResult=undefined;this.nativeOwned=false;
        this.initialMeasurementPending=false;this.cancelAnimations(); this.primary=pointer; this.downPointer=pointer; this.downPosition=this.getPosition(); this.dragged=false;
        this.touch.down(pointer,this.position);
        if(!observeOnly && this.snapshot.config.gestureMode===FxGestureMode.LEGACY && this.interactions.onLongPress!==undefined)this.longPressTimer=setTimeout(() => {
          if(this.primary===undefined) return;
          const current=this.primary;
          this.deliver(this.touch.move({id:current.id,x:current.x,y:current.y,timeMs:pointer.timeMs+500}));
        },500);
        this.observeTouch(this.touchSnapshot(FxTouchPhase.DOWN));
      } else if(this.primary!==undefined && pointer.id===this.primary.id) {
        this.primary=pointer;
        if(event.type===TouchType.Move) {
          const result=this.touch.move(pointer);
          if(!observeOnly)this.deliver(result);
          this.observeTouch(this.touchSnapshot(FxTouchPhase.MOVE));
        } else if(event.type===TouchType.Up) {
          const owned=!observeOnly || this.nativeOwned;
          const result=this.touch.up(pointer);
          if(owned && result.kind==='end' && (result.position.x!==this.position.x || result.position.y!==this.position.y)) {
            this.position=this.dragPosition(result.position); this.dragged=true; this.refresh();
            if(this.boundary!==undefined)this.boundary.moveFrame(this.position);
          }
          const released=this.touchSnapshot(FxTouchPhase.UP);
          const wasDragged=this.dragged;
          this.resetTouch();
          if(released!==undefined) {
            if(owned)this.finishTouch(released,wasDragged,result);
            else {
              this.pendingTap=released;this.pendingTapResult=result;this.pendingTapGeneration=this.interactionGeneration;
              this.observeTouch(released);
            }
          }
        }
      }
    }
  }
  private handleAndroidTouch(event: TouchEvent, observeOnly: boolean): void {
    const changed=event.changedTouches[0];
    if(changed===undefined && event.type!==TouchType.Cancel)return;
    if(event.type===TouchType.Down) {
      if(this.activePointerIds.indexOf(changed.id)>=0)return;
      const secondary=this.activePointerIds.length>0;this.activePointerIds.push(changed.id);
      if(this.primary!==undefined || secondary && !this.nativeOwned)return;
      // A secondary DOWN delivered by an existing capture must still hit this surface.
      if(secondary && (changed.x<0 || changed.y<0 || changed.x>=this.snapshot.size.width || changed.y>=this.snapshot.size.height))return;
      this.pendingTap=undefined;this.pendingTapResult=undefined;this.panStartTime=undefined;
      this.nativeOwned=!observeOnly || secondary;
      this.initialMeasurementPending=false;this.cancelAnimations();
      const pointer=this.androidPointer(changed,event.timestamp);
      this.primary=pointer;this.downPointer=pointer;this.downPosition=this.getPosition();this.dragged=false;
      this.touch.down(pointer,this.position,this.interactions.onClick!==undefined);
      const down=this.touchSnapshot(FxTouchPhase.DOWN);
      const generation=this.interactionGeneration;
      if(down!==undefined && this.interactions.onDown!==undefined)this.runCallback(() => this.interactions.onDown!(this.copyTouch(down)));
      if(generation===this.interactionGeneration)this.observeTouch(down);
      return;
    }
    if(event.type===TouchType.Move) {
      // ArkUI updates may contain several changed contacts; Android MOVE has one action index.
      const id=this.activePointerIds[0];const contacts=event.touches===undefined?event.changedTouches:event.touches;
      const native=contacts.find((value: TouchObject) => value.id===id);
      if(native===undefined || this.primary===undefined || this.primary.id!==id)return;
      this.primary=this.androidPointer(native,event.timestamp);
      if(!observeOnly)this.deliver(this.touch.move(this.primary));
      this.observeTouch(this.touchSnapshot(FxTouchPhase.MOVE));return;
    }
    const owned=this.nativeOwned || !observeOnly;
    if(event.type===TouchType.Up) {
      const index=this.activePointerIds.indexOf(changed.id);if(index<0)return;
      this.activePointerIds.splice(index,1);
      if(!owned && this.activePointerIds.length>0)return;
    } else if(event.type===TouchType.Cancel)this.activePointerIds=[];
    else return;
    if(this.primary!==undefined && changed!==undefined)this.primary=this.androidPointer(changed,event.timestamp);
    const phase=event.type===TouchType.Cancel?FxTouchPhase.CANCEL:FxTouchPhase.UP;
    let released=this.touchSnapshot(phase,event.type===TouchType.Cancel?FxTouchCancelReason.SYSTEM:undefined);
    if(released===undefined && owned && this.parentTerminal!==undefined) {
      released=this.copyTouch(this.parentTerminal);released.phase=phase;released.cancelReason=event.type===TouchType.Cancel?FxTouchCancelReason.SYSTEM:undefined;
      released.position=this.getPosition();released.dragged=false;
      if(changed!==undefined){const pointer=this.androidPointer(changed,event.timestamp);released.pointer={x:pointer.x,y:pointer.y};released.delta={x:pointer.x-released.startPointer.x,y:pointer.y-released.startPointer.y};}
    }
    const result=this.touch.up(this.primary===undefined?{id:-1,x:0,y:0,timeMs:0}:this.primary);
    const wasDragged=this.dragged;this.resetTouch();
    this.nativeOwned=owned && this.activePointerIds.length>0;
    this.parentTerminal=this.nativeOwned?released:undefined;
    if(released===undefined)return;
    if(owned)this.finishTouch(released,wasDragged,result);
    else {
      if(event.type===TouchType.Up) {this.pendingTap=released;this.pendingTapResult=result;this.pendingTapGeneration=this.interactionGeneration;}
      this.observeTouch(released);
    }
  }
  private androidPointer(native: TouchObject, timestamp: number): FxPointer {
    return {id:native.id,x:this.boundary?.displayPointers?native.displayX:native.windowX,
      y:this.boundary?.displayPointers?native.displayY:native.windowY,timeMs:timestamp/1000000};
  }
  /** Terminates the primary pointer once; lifecycle cancellation never settles or clicks. */
  cancelTouch(reason: FxTouchCancelReason = FxTouchCancelReason.HOST_CHANGED): void {
    const event=this.touchSnapshot(FxTouchPhase.CANCEL,reason);
    this.resetTouch();this.nativeOwned=false;this.activePointerIds=[];this.parentTerminal=undefined;this.panStartTime=undefined;this.pendingTap=undefined;this.pendingTapResult=undefined;this.observeTouch(event);
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
  private finishTouch(event: FxTouchSnapshot, wasDragged: boolean, result?: FxTouchResult, observe: boolean = true): void {
    let generation=this.interactionGeneration;
    const android=this.snapshot.config.gestureMode===FxGestureMode.ANDROID_2;
    if(observe && !android)this.observeTouch(event);
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
        // Complete the already handled MOVE without running settle or persistence.
        if(android && wasDragged && this.boundary!==undefined)this.boundary.moveFrame(event.position);
        if(android && observe)this.observeTouch(event);
      }
      return;
    }
    if(generation!==this.interactionGeneration || this.destroyed)return;
    if(android) {
      if(this.snapshot.config.displayMode===FxDisplayMode.Normal && (this.snapshot.config.adsorb || wasDragged))this.settleDrag();
      generation=this.interactionGeneration;
      const up=this.interactions.onUp;if(up!==undefined)this.runCallback(() => up(this.copyTouch(event)));
      if(generation!==this.interactionGeneration || this.destroyed)return;
      if(result!==undefined)this.deliver(result);
      if(observe && generation===this.interactionGeneration)this.observeTouch(event);
    } else {
      if(result!==undefined)this.deliver(result);
      if(generation===this.interactionGeneration && wasDragged)this.settleDrag();
    }
  }
  private dragPosition(point: FxPoint): FxPoint {
    const target=this.snapshot.config.boundaryMode===FxBoundaryMode.ANDROID_2 ? clamp(point,bounds(this.getGeometry(),true)):point;
    if(this.snapshot.config.gestureMode===FxGestureMode.ANDROID_2 && this.boundary?.displayPointers && this.context!==undefined) {
      const density=this.context.vp2px(1);return {x:Math.trunc(target.x*density)/density,y:Math.trunc(target.y*density)/density};
    }
    return target;
  }
  private deliver(result: FxTouchResult): void {
    try {
      if(result.kind==='drag') {
        this.dragged=true; clearTimeout(this.longPressTimer); this.position=this.dragPosition(result.position); this.refresh();
        if(this.boundary!==undefined)this.boundary.moveFrame(this.position);
        if(this.interactions.onDrag!==undefined) {
          const callback=this.interactions.onDrag; this.runCallback(() => callback(this.getPosition()));
        }
      } else if(result.kind==='click' && this.interactions.onClick!==undefined) {this.touch.commitClick();this.runCallback(this.interactions.onClick);}
      else if(result.kind==='longPress' && this.interactions.onLongPress!==undefined && (this.snapshot.config.gestureMode!==FxGestureMode.ANDROID_2 || this.interactions.onClick!==undefined)) this.runCallback(this.interactions.onLongPress);
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
