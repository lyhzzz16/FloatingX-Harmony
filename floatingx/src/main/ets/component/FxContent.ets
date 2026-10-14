import { UIContext } from '@ohos.arkui.UIContext';
import { ComponentContent } from '@ohos.arkui.node';
import { Content, NodeContent, FrameNode, LayoutConstraint, Position } from '@ohos.arkui.node';
import { FxError } from '../core/FxError';
import { FxSize } from '../core/FxTypes';

export interface FxContentMount { content: Content; dispose(): void; measure?(): FxSize | undefined; observeSize?(listener: (size: FxSize) => void): void; observeLayout?(listener: (size: FxSize) => void): void; }
export interface FxContentSource { size: FxSize; create(context: UIContext): FxContentMount; }
/** Own measurement tree keeps full content constraints independent of the clipped viewport. */
class FxContentFrame extends FrameNode {
  private reference: FxSize;
  completed?: () => void;
  private requested: number = 0;
  private measuredRevision: number = -1;
  private notifiedRevision: number = -1;
  private notifiedSize: FxSize = {width:0,height:0};
  private notifiedDensity: number = 0;
  private ownerContext: UIContext;
  requestLayout(): void {this.requested++;this.setNeedsLayout();}
  onLayout(position: Position): void {
    this.setLayoutPosition(position);
    for(let i=0;i<this.getChildrenCount();i++) {const child=this.getChild(i);if(child!==null)child.layout({x:0,y:0});}
    const revision=this.requested;
    // Notify after native layout traversal; callbacks may update content or move the float.
    Promise.resolve().then(() => {
      if(revision!==this.requested || this.measuredRevision!==revision || this.completed===undefined)return;
      const size=this.getMeasuredSize();const density=this.ownerContext.vp2px(1);
      if(this.notifiedRevision===revision && this.notifiedSize.width===size.width &&
        this.notifiedSize.height===size.height && this.notifiedDensity===density)return;
      this.notifiedRevision=revision;this.notifiedSize={width:size.width,height:size.height};this.notifiedDensity=density;
      this.completed();
    });
  }
  constructor(context: UIContext, size: FxSize) {
    super(context);this.ownerContext=context;this.reference={width:context.vp2px(size.width),height:context.vp2px(size.height)};
  }
  onMeasure(constraint: LayoutConstraint): void {
    const full: LayoutConstraint={minSize:{width:0,height:0},
      maxSize:{width:Math.max(constraint.maxSize.width,this.reference.width),height:Math.max(constraint.maxSize.height,this.reference.height)},
      percentReference:this.reference};
    const size: FxSize={width:0,height:0};
    for(let i=0;i<this.getChildrenCount();i++) {
      const child=this.getChild(i);
      if(child!==null) {child.measure(full);const measured=child.getMeasuredSize();size.width=Math.max(size.width,measured.width);size.height=Math.max(size.height,measured.height);}
    }
    this.setMeasuredSize(size); this.measuredRevision=this.requested;
  }
}
class FxTypedMount<T extends Object> implements FxContentMount {
  content: NodeContent;
  private node: ComponentContent<T>;
  private frame: FxContentFrame;
  private disposed: boolean = false;
  private context: UIContext;
  private listener?: (size: FxSize) => void;
  private layoutListener?: (size: FxSize) => void;
  private waitResolve?: () => void;
  private waitReject?: (error: FxError) => void;
  private release: () => void;
  constructor(context: UIContext, node: ComponentContent<T>, size: FxSize, release: () => void) {
    this.node=node;this.release=release;this.context=context;
    this.content=new NodeContent();this.frame=new FxContentFrame(context,size);
    this.frame.completed=() => {
      if(this.disposed)return;const full=this.measure();
      if(full===undefined){this.cancelLayout('INVALID_GEOMETRY');return;}
      const resolve=this.waitResolve;const reject=this.waitReject;this.waitResolve=undefined;this.waitReject=undefined;
      try {if(this.layoutListener!==undefined)this.layoutListener(full);if(resolve!==undefined)resolve();}
      catch(_) {if(reject!==undefined)reject(new FxError('LAYOUT_CANCELED','Content layout observer failed'));}
    };
    // ContentSlot mounts NodeContent; ComponentContent stays private and typed.
    try {this.frame.addComponentContent(node);this.content.addFrameNode(this.frame);
      this.frame.commonEvent.setOnSizeChange(() => {if(this.disposed)return;const size=this.measure();if(size!==undefined && this.listener!==undefined)this.listener(size);});
    }
    catch(error) {
      try {this.frame.commonEvent.setOnSizeChange(undefined);}
      finally {try {this.content.removeFrameNode(this.frame);} finally {this.frame.dispose();}}
      throw error as Error;
    }
  }
  measure(): FxSize | undefined {
    if(this.disposed)return undefined;
    const size=this.frame.getMeasuredSize();
    if(!Number.isFinite(size.width) || !Number.isFinite(size.height) || size.width<=0 || size.height<=0)return undefined;
    return {width:this.context.px2vp(size.width),height:this.context.px2vp(size.height)};
  }
  observeLayout(listener: (size: FxSize) => void): void {if(!this.disposed)this.layoutListener=listener;}
  waitForLayout(): Promise<void> {
    this.cancelLayout('LAYOUT_SUPERSEDED');
    if(this.disposed)return Promise.reject(new FxError('DESTROYED','Content mount is disposed'));
    const result=new Promise<void>((resolve,reject) => {this.waitResolve=resolve;this.waitReject=reject;});
    // Register before requesting native work; even a same-size update needs a new measured layout.
    result.catch(() => {});
    try {this.frame.requestLayout();} catch(_) {this.cancelLayout('LAYOUT_CANCELED');}
    return result;
  }
  cancelLayout(code: string): void {
    const reject=this.waitReject;this.waitResolve=undefined;this.waitReject=undefined;
    if(reject!==undefined)reject(new FxError(code,'Pending content layout was invalidated'));
  }
  observeSize(listener: (size: FxSize) => void): void {if(!this.disposed)this.listener=listener;}
  dispose(): void {
    if(this.disposed) return;this.disposed=true;this.listener=undefined;this.layoutListener=undefined;this.frame.completed=undefined;this.cancelLayout('DESTROYED');
    let failure: Error | undefined;
    try {this.frame.commonEvent.setOnSizeChange(undefined);} catch(error) {failure=error as Error;}
    try {this.release();} catch(error) {if(failure===undefined)failure=error as Error;}
    try {this.content.removeFrameNode(this.frame);} catch(error) {if(failure===undefined)failure=error as Error;}
    // dispose(), unlike disposeTree(), does not recursively dispose our builder node.
    try {this.frame.dispose();} catch(error) {if(failure===undefined)failure=error as Error;}
    try {this.node.dispose();} catch(error) {if(failure===undefined)failure=error as Error;}
    if(failure!==undefined) throw failure;
  }
}
/** Builder parameters remain typed; renderer receives the native non-generic Content base. */
class FxTypedSource<T extends Object> implements FxContentSource {
  private nodes: ComponentContent<T>[] = [];
  private mounts: FxTypedMount<T>[] = [];
  private revision: number = 0;
  readonly builder: WrappedBuilder<[T]>;
  private params: T;
  size: FxSize;
  constructor(builder: WrappedBuilder<[T]>, params: T, size: FxSize) {
    if(builder===undefined || builder===null || typeof builder.builder!=='function' || params===undefined || params===null || typeof params!=='object' || size===undefined || !Number.isFinite(size.width) || !Number.isFinite(size.height) || size.width<=0 || size.height<=0) {
      throw new FxError('INVALID_CONFIG','Content requires a wrapped builder, object parameters and positive vp size');
    }
    this.builder=builder;this.params=params;this.size={width:size.width,height:size.height};
  }
  create(context: UIContext): FxContentMount {
    const node = new ComponentContent<T>(context, this.builder, this.params);
    try {
      const mount=new FxTypedMount<T>(context,node,this.size,() => {
        const index=this.nodes.indexOf(node);if(index>=0) {this.nodes.splice(index,1);this.mounts.splice(index,1);}
      });
      this.nodes.push(node);this.mounts.push(mount);return mount;
    } catch(error) {node.dispose();throw error as Error;}
  }
  cancelLayout(code: string): void {this.revision++;for(let i=0;i<this.mounts.length;i++)this.mounts[i].cancelLayout(code);}
  async updateAndWait(params: T, valid: () => boolean): Promise<() => boolean> {
    this.cancelLayout('LAYOUT_SUPERSEDED');const revision=this.revision;
    await Promise.resolve();
    if(!valid())throw new FxError('DESTROYED','Content update was canceled');
    if(revision!==this.revision)throw new FxError('LAYOUT_SUPERSEDED','Content update was superseded');
    if(this.mounts.length===0)throw new FxError('NO_HOST','A mounted content tree is required for layout completion');
    this.params=params;
    const waiting: Promise<void>[]=[];
    try {
      for(let i=0;i<this.nodes.length;i++) {this.nodes[i].update(params);waiting.push(this.mounts[i].waitForLayout());}
      await Promise.all(waiting);
    } catch(error) {if(revision===this.revision)this.cancelLayout('LAYOUT_CANCELED');throw error as Error;}
    if(!valid())throw new FxError('DESTROYED','Content update was canceled');
    if(revision!==this.revision)throw new FxError('LAYOUT_SUPERSEDED','Content update was superseded');
    return () => revision===this.revision;
  }
  async update(params: T, valid: () => boolean = () => true): Promise<void> {
    this.cancelLayout('LAYOUT_SUPERSEDED');
    // A microtask boundary gives synchronous cancel priority before any native update.
    await Promise.resolve();
    if (!valid()) throw new FxError('DESTROYED', 'Content update was canceled');
    this.params = params;
    for (let i = 0; i < this.nodes.length; i++) this.nodes[i].update(params);
  }
}

// Weak association keeps the native allocation protocol outside the consumer-visible class.
const sources: WeakMap<Object,FxContentSource> = new WeakMap();
export function contentSource<T extends Object>(content: FxContent<T>): FxContentSource {
  const source=sources.get(content);
  if(source===undefined)throw new FxError('INVALID_CONFIG','Content source is unavailable');
  source.size=content.size;return source;
}
/** Public typed builder/value surface; installed adapters exclusively own native mounts. */
export class FxContent<T extends Object> {
  readonly builder: WrappedBuilder<[T]>;
  size: FxSize;
  private source: FxTypedSource<T>;
  constructor(builder: WrappedBuilder<[T]>, params: T, size: FxSize) {
    this.source=new FxTypedSource<T>(builder,params,size);this.builder=builder;this.size=this.source.size;
    sources.set(this,this.source);
  }
  update(params: T, valid: () => boolean = () => true): Promise<void> {return this.source.update(params,valid);}
  updateAndWait(params: T, valid: () => boolean): Promise<() => boolean> {return this.source.updateAndWait(params,valid);}
  cancelLayout(code: string): void {this.source.cancelLayout(code);}
}
