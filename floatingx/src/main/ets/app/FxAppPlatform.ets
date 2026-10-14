import { ComponentContent } from '@ohos.arkui.node';
import { FxPlatform, FxScope, FxEventType } from '../core/FxPlatform';
import { FxController } from '../core/FxController';
import { FxConfig } from '../core/FxConfig';
import { FxError } from '../core/FxError';
import { FxPoint, FxSize, FxGeometrySnapshot, FxLayoutListener, FxTouchCancelReason } from '../core/FxTypes';
import { FxGeometryInput } from '../geometry/FxGeometry';
import { FxContentSource } from '../component/FxContent';
import { FxScopePlatform, FxScopeSnapshot, FxInteractions } from '../scope/FxScopePlatform';
import { FxPagePolicy, copyPagePolicy, allowsPage } from './FxPageFilter';
import { FxWindowHost } from './FxWindowHost';
import { FxAppLayerParams, createAppLayer } from './FxAppFloatLayer';

/** Native app-window owner; one scope engine supplies rendering, gesture, geometry and storage readback. */
export class FxAppPlatform implements FxPlatform {
  readonly actualScope: FxScope = FxScope.APP;
  private host: FxWindowHost;
  private source?: FxContentSource;
  private engine: FxScopePlatform;
  private policy: FxPagePolicy;
  private layer?: ComponentContent<FxAppLayerParams>;
  private controller?: FxController;
  private releaseHost?: () => void;
  private releaseBinding?: () => void;
  private releaseView?: () => void;
  private destroyed: boolean = false;
  private revision: number = 0;
  interactions: FxInteractions;
  constructor(host: FxWindowHost, source: FxContentSource, policy: FxPagePolicy = {mode:'blacklist',names:[]}, interactions: FxInteractions = {}) {
    if(!host.isValid()) throw new FxError('NO_HOST','Window host is disposed');
    this.host=host; this.source=source; this.policy=copyPagePolicy(policy); this.interactions=interactions; this.engine=new FxScopePlatform(interactions);
    this.releaseView=this.engine.subscribe(() => { if(this.layer!==undefined && !this.destroyed && host.isValid()) this.layer.update(new FxAppLayerParams(this,++this.revision)); });
    this.releaseHost=host.subscribe(() => this.syncEligibility());
  }

  bindController(controller: FxController): void {
    if(this.destroyed || !this.host.isValid()) throw new FxError('NO_HOST','Window host is disposed');
    if(this.controller!==undefined) throw new FxError('INVALID_CONFIG','App platform already bound');
    this.controller=controller; this.engine.bindController(controller,false); this.releaseBinding=this.host.bind(controller); this.syncEligibility();
  }
  getGeometrySnapshot(): FxGeometrySnapshot {return this.engine.getGeometrySnapshot();}
  subscribeLayout(listener: FxLayoutListener): () => void {return this.engine.subscribeLayout(listener);}
  cancelTouch(reason: FxTouchCancelReason): void {this.engine.cancelTouch(reason);}
  getSnapshot(): FxScopeSnapshot { return this.engine.getSnapshot(); }
  getGeometry(): FxGeometryInput { return this.engine.getGeometry(); }
  getPosition(): FxPoint { return this.engine.getPosition(); }
  isHostVisible(): boolean { return this.eligible(); }
  isReadyToShow(): boolean { return this.layer!==undefined && this.engine.isHostVisible(); }
  subscribeLifecycle(listener: (type: FxEventType) => void): () => void { return this.engine.subscribeLifecycle(listener); }
  layoutHost(size: FxSize, origin: FxPoint = {x:0,y:0}): void {
    if(this.destroyed || !this.host.isValid() || this.layer===undefined) return;
    this.host.measure(size,origin);
    this.syncViewport();this.syncEligibility();
  }
  layoutContent(size: FxSize): void { if(!this.destroyed && this.host.isValid()) this.engine.layoutContent(size); }
  handleTouch(event: TouchEvent, observeOnly: boolean = false): void { if(this.isHostVisible() && this.isReadyToShow()) this.engine.handleTouch(event,observeOnly); }
  canStartPan(event: BaseGestureEvent): boolean {return this.engine.canStartPan(event);}
  handlePan(event: GestureEvent, starting: boolean = false): void {this.engine.handlePan(event,starting);}
  completeSurfaceTap(): void {this.engine.completeSurfaceTap();}
  cancelAnimations(): void { this.engine.cancelAnimations(); }
  async create(): Promise<void> {
    this.assertAlive(); if(this.layer!==undefined) return;
    if(this.source===undefined) throw new FxError('NO_HOST','App content source is released');
    this.engine.mountHost(this.host.uiContext,this.source);
    try {
      this.layer=createAppLayer(this.host.uiContext,this); this.host.add(this.layer);
      if(this.eligible()) this.host.show(this.layer); else this.host.hide(this.layer);
      await this.engine.create();
    } catch(error) {
      const layer=this.layer; this.layer=undefined;
      try { if(layer!==undefined) this.host.remove(layer); }
      finally { try { if(layer!==undefined) layer.dispose(); } finally { this.engine.unmountHost(); } }
      throw error as Error;
    }
  }
  async applyConfig(config: FxConfig): Promise<void> {
    this.assertAlive();
    // Validate authority before changing either configuration or geometry.
    this.host.getViewport(config.safeAreaPolicy);
    await this.engine.applyConfig(config);
    this.syncViewport();
  }
  async show(): Promise<void> {
    this.assertAlive(); if(!this.isHostVisible() || !this.isReadyToShow() || this.layer===undefined) return;
    this.host.show(this.layer); await this.engine.show();
  }
  async hide(): Promise<void> {
    const layer=this.layer;
    // The shared fade engine rolls its snapshot back if the final native hide rejects.
    await this.engine.hide(() => { if(layer!==undefined && !this.destroyed) this.host.hide(layer); });
  }
  async move(point: FxPoint, animate: boolean): Promise<FxPoint> { this.assertAlive(); return this.engine.move(point,animate); }
  async destroy(): Promise<void> {
    if(this.destroyed) return; this.destroyed=true; this.source=undefined; this.engine.cancelAnimations();
    const layer=this.layer; this.layer=undefined;
    try { if(layer!==undefined) this.host.remove(layer); }
    finally {
      try { if(layer!==undefined) layer.dispose(); }
      finally {
        try { await this.engine.destroy(); }
        finally {
          if(this.releaseView!==undefined) this.releaseView(); if(this.releaseHost!==undefined) this.releaseHost();
          if(this.releaseBinding!==undefined) this.releaseBinding(); this.controller=undefined;
        }
      }
    }
  }
  private syncViewport(): void {
    if(!this.engine.isHostVisible() && this.layer===undefined)return;
    const viewport=this.host.getViewport(this.engine.getSnapshot().config.safeAreaPolicy);
    const current=this.engine.getGeometry().viewport;
    if(current.size.width===viewport.size.width && current.size.height===viewport.size.height && current.insets.left===viewport.insets.left && current.insets.top===viewport.insets.top && current.insets.right===viewport.insets.right && current.insets.bottom===viewport.insets.bottom)return;
    this.engine.layoutHost(viewport.size,viewport.insets);
  }
  private eligible(): boolean { return !this.destroyed && this.host.isForeground() && allowsPage(this.policy,this.host.getPage()); }
  private syncEligibility(): void {
    if(this.destroyed) return;
    try {this.syncViewport();}catch(error){this.controller?.reportError(error as Error);}
    if(!this.eligible()){this.engine.cancelAnimations();this.engine.cancelTouch();}
    if(this.layer!==undefined && this.host.isValid()) {
      try { if(this.eligible()) this.host.show(this.layer); else this.host.hide(this.layer); }
      catch(error) { if(this.controller!==undefined) this.controller.reportError(error as Error); }
    }
    if(this.controller!==undefined) this.controller.setHostVisible(this.isHostVisible()).catch(() => {});
  }
  private assertAlive(): void { if(this.destroyed || !this.host.isValid()) throw new FxError('NO_HOST','App window host is disposed'); }
}
