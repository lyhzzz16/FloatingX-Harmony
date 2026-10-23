import common from '@ohos.app.ability.common';
import { FrameNode, NodeController, RenderNode, DrawContext } from '@ohos.arkui.node';
import { UIContext } from '@ohos.arkui.UIContext';
import drawing from '@ohos.graphics.drawing';
import { FloatingX, FloatingXHost, FxContent, FxControl, FxConfig, FxWindowHost, FxBoundaryMode,
  FxGestureMode, FxFocusPolicy, FxState, FxSize, FxEvent } from 'floatingx';
import { DemoOwner, DemoPageOwner } from '../entryability/DemoOwner';
import { RenderProbeBackground } from '../entryability/RenderProbeBackground';

/** This fixture reports its content size only from a genuine native draw callback. */
class DrawProbeNode extends RenderNode {
  painted: () => void = () => {};
  draw(context: DrawContext): void {
    const brush=new drawing.Brush();
    brush.setColor({alpha:255,red:40,green:130,blue:190});
    context.canvas.attachBrush(brush);
    context.canvas.drawRect({left:0,top:0,right:1,bottom:1});
    context.canvas.detachBrush();
    this.painted();
  }
}
class DrawProbeController extends NodeController {
  private frame?: FrameNode;
  private render?: DrawProbeNode;
  private pending?: () => void;
  private reject?: (error: Error) => void;
  private deadline: number = -1;
  makeNode(context: UIContext): FrameNode {
    this.frame=new FrameNode(context);
    this.render=new DrawProbeNode();
    this.render.frame={x:0,y:0,width:1,height:1};
    this.render.painted=() => {const pending=this.pending;this.pending=undefined;if(pending!==undefined)pending();};
    this.frame.getRenderNode()?.appendChild(this.render);
    return this.frame;
  }
  waitForDraw(wide: boolean,record: () => void): Promise<FxSize> {
    this.cancelWait();
    return new Promise<FxSize>((resolve,reject) => {
      this.reject=reject;
      this.pending=() => {
        clearTimeout(this.deadline);this.deadline=-1;this.reject=undefined;
        // Size is produced here, never in mount, a timer or a synthetic draw invocation.
        const size: FxSize={width:wide?280:220,height:wide?144:112};
        record();resolve(size);
      };
      this.deadline=setTimeout(() => this.cancelWait('Native draw did not arrive'),5000);
      this.render?.invalidate();
    });
  }
  cancelWait(message: string = 'Draw wait canceled'): void {
    clearTimeout(this.deadline);this.deadline=-1;this.pending=undefined;
    const reject=this.reject;this.reject=undefined;if(reject!==undefined)reject(new Error(message));
  }
  release(): void {
    this.cancelWait();this.render?.dispose();this.render=undefined;this.frame?.dispose();this.frame=undefined;
  }
}
class DrawParams {
  probe: DrawProbeController; width: number; height: number;
  next: () => void; close: () => void; hidden: boolean;
  constructor(probe: DrawProbeController,width: number,height: number,
    next: () => void,close: () => void,hidden: boolean = false) {
    this.probe=probe;this.width=width;this.height=height;this.next=next;this.close=close;this.hidden=hidden;
  }
}
@Builder
function drawContent(params: DrawParams) {
  Stack({alignContent:Alignment.TopStart}) {
    NodeContainer(params.probe).width(1).height(1)
    Column({space:4}) {
      Text('原生 draw → 布局').fontSize(16)
      Row({space:8}) {Button('浮窗更新').onClick(params.next);Button('浮窗关闭').onClick(params.close)}
    }.width('100%').height('100%')
  }.width(params.width).height(params.height).backgroundColor('#B7DDFF')
    .visibility(params.hidden?Visibility.Hidden:Visibility.Visible)
}
class DrawSession {
  probe: DrawProbeController = new DrawProbeController();
  control?: FxControl<DrawParams>;
  config: FxConfig = new FxConfig({layoutOnly:true,boundaryMode:FxBoundaryMode.ANDROID_2,
    gestureMode:FxGestureMode.ANDROID_2,contentOwnsTap:true,focusPolicy:FxFocusPolicy.NON_FOCUSABLE,
    adsorb:false,position:{x:24,y:320}});
  size: FxSize = {width:1,height:1};
  revision: number = 0;
  closed: boolean = false;
  shown: Promise<void> = Promise.resolve();
  markShown: () => void = () => {};
  expectShow(): void {this.shown=new Promise<void>(resolve => {this.markShown=resolve;});}
  mode: string; hidden: boolean;
  constructor(mode: string,hidden: boolean) {this.mode=mode;this.hidden=hidden;}
}

@Component
export struct RenderLayoutDemo {
  @State private message: string = '尺寸只由 RenderNode.draw 产生；超时判失败';
  @State private scopeEpochs: number[] = [];
  private scopeControl?: FxControl<DrawParams>;
  private nextScopeEpoch: number = 0;
  @State private lowerClicks: number = 0;
  private owner: DemoPageOwner = new DemoPageOwner();
  private session?: DrawSession;
  private busy: boolean = false;
  aboutToAppear(): void {this.owner.activate();}
  aboutToDisappear(): void {RenderProbeBackground.pending=undefined;this.run(this.close());this.run(this.owner.close());}
  private record(session: DrawSession,event: string): void {
    const value=session.mode+(session.hidden?'/Hidden':'')+' r='+session.revision+' '+event;
    console.info('FxRender '+value);if(this.owner.isActive() && this.session===session)this.message=value;
  }
  private params(session: DrawSession): DrawParams {
    return new DrawParams(session.probe,session.size.width,session.size.height,
      () => this.run(this.update()),() => this.run(this.close()),session.hidden);
  }
  private async close(): Promise<void> {
    const session=this.session;this.session=undefined;this.scopeEpochs=[];this.scopeControl=undefined;
    if(session===undefined)return;
    session.closed=true;session.markShown();session.probe.cancelWait();
    try {await session.control?.cancel();} finally {session.probe.release();}
  }
  private async open(mode: string,hidden: boolean = false,suite: boolean = false,reveal: boolean = true): Promise<void> {
    await this.close();if(!this.owner.isActive())return;
    const session=new DrawSession(mode,hidden);this.session=session;
    const content=new FxContent(wrapBuilder(drawContent),this.params(session),session.size);
    const events=(event: FxEvent) => {
      this.record(session,'event='+event.type);if(event.type==='show')session.markShown();
    };
    let control: FxControl<DrawParams>;
    if(mode==='Scope')control=FloatingX.createScope({content:content,config:session.config,events:events});
    else if(mode==='App') {
      const host=this.getUIContext().getSharedLocalStorage()?.get<FxWindowHost>('fxWindowHost');
      if(host===undefined)throw new Error('App host not ready');
      control=FloatingX.installApp({tag:'render-probe-app',host:host,content:content,config:session.config,events:events});
    } else {
      control=FloatingX.installSystem({tag:'render-probe-system',
        context:this.getUIContext().getHostContext() as common.UIAbilityContext,
        content:content,size:session.size,config:session.config,events:events});
      this.getUIContext().getSharedLocalStorage()?.get<DemoOwner>('fxSystemOwner')?.add(control);
    }
    session.control=control;this.owner.hold(control);if(mode==='Scope'){this.scopeControl=control;this.scopeEpochs=[++this.nextScopeEpoch];}
    await this.present(session,false,reveal,true);
    if(suite) {
      await this.present(session,true,true);await this.present(session,true,true);await this.present(session,false,true);
      await control.hide();this.record(session,'hidden isShow='+control.isShow());
      await this.present(session,false,true,true);this.record(session,'SUITE PASS');
    }
  }
  private async present(session: DrawSession,wide: boolean,reveal: boolean,show: boolean = false): Promise<void> {
    const control=session.control;if(control===undefined || session.closed)throw new Error('Session closed');
    const revision=++session.revision;
    session.config.layoutOnly=true;await control.updateConfig(session.config);
    if(show) {
      session.expectShow();await control.show();
      if(control.getState()!==FxState.PREPARED)await session.shown;
    }
    const drawn=session.probe.waitForDraw(wide,() => this.record(session,'DRAW state='+control.getState()+' isShow='+control.isShow()));
    drawn.catch(() => {});
    await control.updateContent(this.params(session));
    const size=await drawn;
    if(session.closed || revision!==session.revision)throw new Error('Stale draw');
    if(control.isShow() || control.getState()!==FxState.PREPARED)throw new Error('Prelayout state was not ready');
    session.size=size;
    const geometry=await control.updateContentAndWaitForLayout(this.params(session));
    if(session.closed || revision!==session.revision)throw new Error('Stale layout');
    if(Math.abs(geometry.content.width-size.width)>0.5 || Math.abs(geometry.content.height-size.height)>0.5)throw new Error('Wrong content geometry');
    this.record(session,'LAYOUT size='+geometry.content.width+'x'+geometry.content.height+' version='+geometry.layoutVersion);
    await control.move(24,320);
    this.record(session,'GEOMETRY position='+control.getX()+','+control.getY());
    if(reveal) {session.config.layoutOnly=false;await control.updateConfig(session.config);}
    this.record(session,(reveal?'PRESENT':'HOLD')+' state='+control.getState()+' isShow='+control.isShow());
  }
  private async update(): Promise<void> {
    if(this.busy)return;this.busy=true;
    try {const session=this.session;if(session!==undefined)await this.present(session,session.size.width<250,true);}
    finally {this.busy=false;}
  }
  private run(work: Promise<void>): void {work.catch((error: Error) => {console.error('FxRender FAIL '+error.message);if(this.owner.isActive())this.message='FAIL '+error.message;});}
  @Builder private hostBackground() {
    Column() {Button('底层按钮 '+this.lowerClicks).margin({top:80}).onClick(() => {this.lowerClicks++;console.info('FxRender lower click='+this.lowerClicks);})}
      .width('100%').height('100%').backgroundColor('#F3F4F6')
  }
  build() {
    Column({space:6}) {
      Text('绘制驱动预布局验证').fontSize(18)
      Text(this.message).fontSize(12).height(44)
      Row({space:6}) {
        Button('Scope 全流程').fontSize(12).onClick(() => this.run(this.open('Scope',false,true)))
        Button('App 全流程').fontSize(12).onClick(() => this.run(this.open('App',false,true)))
        Button('System 全流程').fontSize(12).onClick(() => this.run(this.open('System',false,true)))
      }
      Row({space:6}) {
        Button('透明停留').fontSize(12).onClick(() => this.run(this.open('App',false,false,false)))
        Button('Hidden 对照').fontSize(12).onClick(() => this.run(this.open('App',true,false,false)))
        Button('更新并展示').fontSize(12).onClick(() => this.run(this.update()))
        Button('销毁').fontSize(12).onClick(() => this.run(this.close()))
      }
      Button('Home 后系统首显：现在按 Home').fontSize(12).onClick(() => {
        RenderProbeBackground.pending=() => this.run(this.open('System',false,true));
        this.message='已准备；按 Home 后由宿主后台事件启动测试';
      })
      if(this.scopeEpochs.length>0) {
        ForEach(this.scopeEpochs,(_epoch: number) => {
          FloatingXHost({control:this.scopeControl!,host:() => {this.hostBackground();}}).layoutWeight(1)
        },(epoch: number) => epoch.toString())
      } else {this.hostBackground()}
    }.width('100%').height('100%').padding(12)
  }
}
