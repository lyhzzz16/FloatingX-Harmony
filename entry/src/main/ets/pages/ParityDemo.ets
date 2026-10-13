import { FloatingX, FloatingXHost, FxContent, FxControl, FxConfig, FxBoundaryMode,
  FxReleaseDecision, FxTouchSnapshot } from 'floatingx';
import { DemoPageOwner } from '../entryability/DemoOwner';
class ParityParams {
  width: number; label: string;
  constructor(width: number,label: string) {this.width=width;this.label=label;}
}
@Builder
function parityContent(params: ParityParams) {
  Text(params.label).width(params.width).height(72).backgroundColor('#B7DDFF').borderRadius(12).textAlign(TextAlign.Center)
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
  private config: FxConfig = new FxConfig({boundaryMode:FxBoundaryMode.ANDROID_2,
    halfHide:true,halfHideRatio:0.5,rebound:true,adsorb:false,position:{x:30,y:80}});
  private control: FxControl<ParityParams> = FloatingX.createScope({
    config:this.config,
    content:new FxContent(wrapBuilder(parityContent),new ParityParams(160,'拖动 / 点按'),{width:160,height:72}),
    interactions:{
      onTouch:(event: FxTouchSnapshot) => {this.message=event.phase+' delta='+event.delta.x.toFixed(1)+','+event.delta.y.toFixed(1)+' x='+event.position.x.toFixed(1);},
      onRelease:() => this.consumed?FxReleaseDecision.CONSUMED:FxReleaseDecision.DEFAULT,
      onClick:() => {this.message='默认点击';}
    }
  });
  aboutToAppear(): void {
    this.owner.activate([this.control]);
    this.releaseLayout=this.control.subscribeLayout(value => {this.geometry='layout='+value.layoutVersion+' measured='+value.measured+' '+value.content.width+'×'+value.content.height;});
    this.run(this.control.show());
  }
  aboutToDisappear(): void {if(this.releaseLayout!==undefined)this.releaseLayout();this.run(this.owner.close());}
  private run(work: Promise<void>): void {work.catch((error: Error) => {if(this.owner.isActive())this.message=error.message;});}
  private async resize(): Promise<void> {
    this.expanded=!this.expanded;
    const value=await this.control.updateContentAndWaitForLayout(new ParityParams(this.expanded?240:160,'原节点更新内容'));
    if(this.owner.isActive())this.message='完成：'+value.content.width+'×'+value.content.height+'，instance='+value.instanceId;
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
        Button('隐藏').onClick(() => this.run(this.control.hide()))
        Button('显示').onClick(() => this.run(this.control.show()))
      }
      FloatingXHost({control:this.control,host:() => {this.hostBackground();}}).layoutWeight(1)
    }.padding(12).width('100%').height('100%')
  }
}
