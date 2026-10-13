import window from '@ohos.window';
import { UIContext, OverlayManager } from '@ohos.arkui.UIContext';
import { ComponentContent } from '@ohos.arkui.node';
import { FxAvoidRect, intersectAvoidAreas } from '../geometry/FxAvoidArea';
import { FxController } from '../core/FxController';
import { FxError } from '../core/FxError';
import { FxViewport, FxSize, FxPoint, FxSafeAreaPolicy, FxInsets } from '../core/FxTypes';

/** One loaded WindowStage. No process-global window or overlay operations. */
export class FxWindowHost {
  readonly uiContext: UIContext;
  readonly overlay: OverlayManager;
  private mainWindow: window.Window;
  private valid: boolean = true;
  private foreground: boolean;
  private page?: string;
  private listeners: (() => void)[] = [];
  private controllers: FxController[] = [];
  private disposal?: Promise<void>;
  private origin: FxPoint = {x:0,y:0};
  private measured: FxSize = {width:1,height:1};
  private windowEvent: (event: window.WindowEventType) => void = (event) => {
    if(!this.valid) return;
    if(event===window.WindowEventType.WINDOW_SHOWN) this.foreground=true;
    else if(event===window.WindowEventType.WINDOW_HIDDEN) this.foreground=false;
    this.notify();
  };
  private sizeEvent: (size: window.Size) => void = (_size) => { this.notify(); };
  private avoidEvent: (area: window.AvoidAreaOptions) => void = (_area) => { this.notify(); };
  private constructor(mainWindow: window.Window) {
    this.mainWindow=mainWindow; this.uiContext=mainWindow.getUIContext(); this.overlay=this.uiContext.getOverlayManager();
    this.foreground=mainWindow.isWindowShowing();
  }
  /** Caller guard covers stage destruction while getMainWindow awaits. Call after loadContent completes. */
  static async create(stage: window.WindowStage, valid: () => boolean = () => true): Promise<FxWindowHost> {
    const mainWindow=await stage.getMainWindow();
    if(!valid()) throw new FxError('NO_HOST','WindowStage was destroyed during host creation');
    const host=new FxWindowHost(mainWindow);
    try {
      mainWindow.on('windowEvent',host.windowEvent); mainWindow.on('windowSizeChange',host.sizeEvent); mainWindow.on('avoidAreaChange',host.avoidEvent);
      return host;
    } catch(error) { await host.dispose(); throw error as Error; }
  }
  isValid(): boolean { return this.valid; }
  isForeground(): boolean { return this.valid && this.foreground; }
  getPage(): string | undefined { return this.page; }
  getViewport(policy: FxSafeAreaPolicy = FxSafeAreaPolicy.HOST): FxViewport {
    if(policy===FxSafeAreaPolicy.EXTEND) {
      const rect=this.mainWindow.getWindowProperties().windowRect;const d=this.uiContext.vp2px(1);
      if(Math.abs(this.origin.x)>0.5 || Math.abs(this.origin.y)>0.5 || Math.abs(this.measured.width-rect.width/d)>0.5 || Math.abs(this.measured.height-rect.height/d)>0.5)
        throw new FxError('CAPABILITY_UNSUPPORTED','App EXTEND requires an already full-window host; the library never changes main-window immersion');
    }
    const insets: FxInsets=policy===FxSafeAreaPolicy.AVOID_SYSTEM?intersectAvoidAreas(this.measured,this.origin,this.uiContext.vp2px(1),this.readAvoidRects()):{left:0,top:0,right:0,bottom:0};
    return {size:{width:this.measured.width,height:this.measured.height},insets:insets};
  }
  /** System avoids require a full-display main window on the same display; a tiny float cannot be the authority. */
  getSystemViewport(displayId: number, size: FxSize, density: number): FxViewport {
    if(!this.valid)throw new FxError('NO_HOST','Avoid-area host is disposed');
    const properties=this.mainWindow.getWindowProperties();const rect=properties.windowRect;
    if(properties.displayId!==displayId || rect.left!==0 || rect.top!==0 || Math.abs(rect.width-size.width*density)>1 || Math.abs(rect.height-size.height*density)>1)
      throw new FxError('CAPABILITY_UNSUPPORTED','System avoid areas require a full-display host on the target display; split-screen and other-display avoid regions are not authoritative');
    return {size:size,insets:intersectAvoidAreas(size,{x:0,y:0},density,this.readAvoidRects())};
  }
  private readAvoidRects(): FxAvoidRect[] {
    if(!this.valid)throw new FxError('NO_HOST','Avoid-area host is disposed');
    const result: FxAvoidRect[]=[];
    const types: window.AvoidAreaType[]=[window.AvoidAreaType.TYPE_SYSTEM,window.AvoidAreaType.TYPE_CUTOUT,window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR];
    try {
      for(let i=0;i<types.length;i++) {
        const area=this.mainWindow.getWindowAvoidArea(types[i]);
        result.push(this.avoidRect(area.topRect,'top'),this.avoidRect(area.bottomRect,'bottom'),
          this.avoidRect(area.leftRect,'left'),this.avoidRect(area.rightRect,'right'));
      }
    } catch(_) {throw new FxError('CAPABILITY_UNSUPPORTED','Main window cannot provide system avoid areas');}
    return result;
  }
  private avoidRect(rect: window.Rect, edge: 'left' | 'top' | 'right' | 'bottom'): FxAvoidRect {
    return {left:rect.left,top:rect.top,width:rect.width,height:rect.height,edge:edge};
  }
  measure(size: FxSize, origin: FxPoint = {x:0,y:0}): void {
    if(this.valid && size.width>0 && size.height>0) {this.measured={width:size.width,height:size.height};this.origin={x:origin.x,y:origin.y};}
  }
  setPage(name: string): void { if(this.valid) { this.page=name; this.notify(); } }
  subscribe(listener: () => void): () => void {
    if(!this.valid) throw new FxError('NO_HOST','Window host is disposed');
    this.listeners.push(listener);
    return () => { const i=this.listeners.indexOf(listener); if(i>=0) this.listeners.splice(i,1); };
  }
  bind(controller: FxController): () => void {
    if(!this.valid) throw new FxError('NO_HOST','Window host is disposed');
    this.controllers.push(controller);
    return () => { const i=this.controllers.indexOf(controller); if(i>=0) this.controllers.splice(i,1); };
  }
  add<T extends Object>(content: ComponentContent<T>): void { if(!this.valid) throw new FxError('NO_HOST','Window host is disposed'); this.overlay.addComponentContent(content); }
  show<T extends Object>(content: ComponentContent<T>): void { if(this.valid) this.overlay.showComponentContent(content); }
  hide<T extends Object>(content: ComponentContent<T>): void { this.overlay.hideComponentContent(content); }
  remove<T extends Object>(content: ComponentContent<T>): void { this.overlay.removeComponentContent(content); }
  dispose(): Promise<void> {
    if(this.disposal!==undefined) return this.disposal;
    this.valid=false; this.foreground=false; // Synchronous invalidation precedes every asynchronous cleanup.
    const controllers=this.controllers.slice(); this.controllers=[];
    let notificationFailure: Error | undefined;
    // Cache the shared promise before user callbacks; reentrant disposal joins it.
    // The microtask starts cleanup after all synchronous notifications have been attempted.
    this.disposal=Promise.resolve().then(() => this.cleanup(controllers,notificationFailure));
    try { this.notify(); } catch(error) { notificationFailure=error as Error; }
    return this.disposal;
  }
  private async cleanup(controllers: FxController[], failure?: Error): Promise<void> {
    try {
      for(let i=0;i<controllers.length;i++) { try { await controllers[i].cancel(); } catch(error) { if(failure===undefined) failure=error as Error; } }
    } finally {
      // Each listener release runs even when a previous native off throws.
      try { this.mainWindow.off('windowEvent',this.windowEvent); } catch(error) { if(failure===undefined) failure=error as Error; }
      try { this.mainWindow.off('windowSizeChange',this.sizeEvent); } catch(error) { if(failure===undefined) failure=error as Error; }
      try { this.mainWindow.off('avoidAreaChange',this.avoidEvent); } catch(error) { if(failure===undefined) failure=error as Error; }
      this.listeners=[];
    }
    if(failure!==undefined) throw failure;
  }
  private notify(): void {
    const listeners=this.listeners.slice(); let failure: Error | undefined;
    for(let i=0;i<listeners.length;i++) {
      try { listeners[i](); } catch(error) { if(failure===undefined) failure=error as Error; }
    }
    if(failure!==undefined) throw failure;
  }
}
