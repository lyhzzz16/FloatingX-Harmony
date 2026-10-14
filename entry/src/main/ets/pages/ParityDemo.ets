import { FloatingX, FloatingXHost, FxContent, FxControl, FxConfig, FxBoundaryMode, FxGestureMode, FxFocusPolicy,
  FxReleaseDecision, FxTouchSnapshot } from 'floatingx';
import { DemoPageOwner } from '../entryability/DemoOwner';
class ParityParams {
  width: number; label: string;
  action: (label: string) => void;
  constructor(width: number,label: string,action: (label: string) => void = () => {}) {this.width=width;this.label=label;this.action=action;}
}
@Builder
function parityContent(params: ParityParams) {
  Column({space:4}) {
    Text(params.label).height(28)
    Row({space:8}) {
      Button('A').onClick(() => params.action('A click')).onTouch((event: TouchEvent) => {params.action('A touch '+event.type.toString());})
      Button('B').onClick(() => params.action('B click')).onTouch((event: TouchEvent) => {params.action('B touch '+event.type.toString());})
    }
  }.width(params.width).height(100).backgroundColor('#B7DDFF').borderRadius(12)
}
/** Generic interaction and layout probe: all release decisions belong to the caller. */
@Component
export struct ParityDemo {
  @State private message: string = '拖动蓝色浮窗；按下、松开、取消均可观察';
  @State private geometry: string = '等待原生布局';
  @State private consumed: boolean = false;
  @State private adsorb: boolean = false;
  @State private expanded: boolean = false;
  private owner: DemoPageOwner = new DemoPageOwner();
  private releaseLayout?: () => void;
  private config: FxConfig = new FxConfig({boundaryMode:FxBoundaryMode.ANDROID_2,gestureMode:FxGestureMode.ANDROID_2,focusPolicy:FxFocusPolicy.NON_FOCUSABLE,
    halfHide:true,halfHideRatio:0.5,rebound:true,adsorb:false,position:{x:30,y:80}});
  private control: FxControl<ParityParams> = FloatingX.createScope({
    config:this.config,
    content:new FxContent(wrapBuilder(parityContent),new ParityParams(160,'整窗拖动 / 原生按钮',label => this.record(label)),{width:160,height:100}),
    interactions:{
      onDown:() => this.record('helper down'),
      onUp:() => this.record('parent up'),
      onTouch:(event: FxTouchSnapshot) => {this.message=event.phase+' delta='+event.delta.x.toFixed(1)+','+event.delta.y.toFixed(1)+' x='+event.position.x.toFixed(1);},
      onRelease:() => {this.record('parent release');return this.consumed?FxReleaseDecision.CONSUMED:FxReleaseDecision.DEFAULT;},
      onClick:() => this.record('parent click'),onLongPress:() => this.record('parent long release')
    }
  });
  aboutToAppear(): void {
    this.owner.activate([this.control]);
    this.releaseLayout=this.control.subscribeLayout(value => {this.geometry='layout='+value.layoutVersion+' measured='+value.measured+' '+value.content.width+'×'+value.content.height;});
    this.run(this.control.show());
  }
  aboutToDisappear(): void {if(this.releaseLayout!==undefined)this.releaseLayout();this.run(this.owner.close());}
  private run(work: Promise<void>): void {work.catch((error: Error) => {if(this.owner.isActive())this.message=error.message;});}
  private record(label: string): void {this.message=label;console.info('FxParity '+label);}
  private async resize(): Promise<void> {
    this.expanded=!this.expanded;
    const value=await this.control.updateContentAndWaitForLayout(new ParityParams(this.expanded?240:160,'原节点更新内容',label => this.record(label)));
    if(this.owner.isActive())this.message='完成：'+value.content.width+'×'+value.content.height+'，instance='+value.instanceId;
  }
  private async prepare(): Promise<void> {
    this.config.layoutOnly=true;await this.control.updateConfig(this.config);await this.control.show();
    const value=await this.control.updateContentAndWaitForLayout(new ParityParams(240,'隐藏测量后显示',label => this.record(label)));
    await this.control.move(value.viewport.size.width-value.content.width,100);
    this.config.layoutOnly=false;await this.control.updateConfig(this.config);this.record('prepared width='+value.content.width);
  }
  @Builder
  hostBackground() {Column(){Text('局部宿主边界（vp）').align(Alignment.Bottom)}.width('100%').height('100%').backgroundColor('#F3F4F6')}
  build() {
    Column({space:8}) {
      Text('Android 2.x 边界 / 触摸 / 布局验证').fontSize(18)
      Text(this.message).fontSize(12)
      Text(this.geometry).fontSize(12)
      Row({space:8}) {
        Button(this.consumed?'接管释放：开':'接管释放：关').onClick(() => {this.consumed=!this.consumed;})
        Button(this.adsorb?'吸附：开':'吸附：关').onClick(() => {this.adsorb=!this.adsorb;this.config.adsorb=this.adsorb;this.run(this.control.updateConfig(this.config));})
      }
      Row({space:8}) {
        Button('更新并等待布局').onClick(() => this.run(this.resize()))
        Button('隐藏测量').onClick(() => this.run(this.prepare()))
        Button('隐藏').onClick(() => this.run(this.control.hide()))
        Button('显示').onClick(() => this.run(this.control.show()))
      }
      FloatingXHost({control:this.control,host:() => {this.hostBackground();}}).layoutWeight(1)
    }.padding(12).width('100%').height('100%')
  }
}
