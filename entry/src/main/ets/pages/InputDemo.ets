import { FloatingX, FxWindowHost, FxContent, FxControl, FxConfig, FxBoundaryMode, FxGestureMode,
  FxReleaseDecision, FxTouchPhase, FxTouchSnapshot } from 'floatingx';
import { DemoPageOwner } from '../entryability/DemoOwner';

class InputParams {
  width: number;
  record: (value: string) => void;
  constructor(width: number,record: (value: string) => void) {this.width=width;this.record=record;}
}
@Builder
function inputContent(params: InputParams) {
  Column({space:8}) {
    Text('浮窗文字 / 间距可起拖').height(32)
    Row({space:16}) {
      Button('A').onClick(() => params.record('A click'))
        .onTouch((event: TouchEvent) => {if(event.type!==TouchType.Move)params.record('A touch='+event.type+' t='+event.timestamp);})
      Button('B').onClick(() => params.record('B click'))
        .onTouch((event: TouchEvent) => {if(event.type!==TouchType.Move)params.record('B touch='+event.type+' t='+event.timestamp);})
    }
  }.width(params.width).height(112).backgroundColor('#B7DDFF').borderRadius(12)
}

/** App overlay above native lists: content tap ownership and hierarchy isolation share one probe. */
@Component
export struct InputDemo {
  @LocalStorageLink('fxHostReady') @Watch('hostReady') private ready: boolean = false;
  @State private contentOwnsTap: boolean = true;
  @State private childClicks: number = 0;
  @State private parentReleases: number = 0;
  @State private lowerDowns: number = 0;
  @State private lowerMoves: number = 0;
  @State private lowerScrolls: number = 0;
  @State private message: string = '等待 App 宿主';
  private owner: DemoPageOwner = new DemoPageOwner();
  private control?: FxControl<InputParams>;
  private config: FxConfig = new FxConfig({boundaryMode:FxBoundaryMode.ANDROID_2,gestureMode:FxGestureMode.ANDROID_2,
    contentOwnsTap:true,adsorb:false,position:{x:30,y:340}});
  private wide: boolean = false;
  private sequence: number = 0;
  private rows: number[] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];
  private columns: number[] = [0,1,2,3,4,5,6,7];
  aboutToAppear(): void {this.owner.activate();this.hostReady();}
  aboutToDisappear(): void {this.run(this.owner.close());}
  private hostReady(): void {
    if(!this.owner.isActive() || this.control!==undefined || !this.ready)return;
    const host=this.getUIContext().getSharedLocalStorage()?.get<FxWindowHost>('fxWindowHost');
    if(host===undefined || !host.isValid())return;
    const control=FloatingX.installApp({tag:'native-input-probe',host:host,config:this.config,
      content:new FxContent(wrapBuilder(inputContent),new InputParams(220,value=>this.record(value)),{width:220,height:112}),
      interactions:{
        onDown:()=>{this.sequence++;this.record('helper DOWN');},
        onTouch:(event: FxTouchSnapshot)=>{if(event.phase!==FxTouchPhase.MOVE)this.record('observer '+event.phase+' pointer='+event.pointerId);},
        onRelease:(event: FxTouchSnapshot)=>{this.parentReleases++;this.record('parent release dragged='+event.dragged);return FxReleaseDecision.DEFAULT;},
        onUp:()=>this.record('parent UP'),onClick:()=>this.record('parent click')
      }});
    if(!this.owner.hold(control))return;
    this.control=control;this.run(control.show());
  }
  private record(value: string): void {
    if(!this.owner.isActive())return;
    if(value==='A click' || value==='B click')this.childClicks++;
    this.message=value;console.info('FxInput seq='+this.sequence+' '+value);
  }
  private lowerTouch(event: TouchEvent): void {
    if(event.type===TouchType.Down)this.lowerDowns++;
    if(event.type===TouchType.Move)this.lowerMoves++;
    if(event.type!==TouchType.Move)console.info('FxInput lower touch='+event.type+' t='+event.timestamp);
  }
  private async resize(): Promise<void> {
    const control=this.control;if(control===undefined)return;
    this.wide=!this.wide;
    const value=await control.updateContentAndWaitForLayout(new InputParams(this.wide?280:220,value=>this.record(value)));
    this.record('layout width='+value.content.width);
  }
  private run(work: Promise<void>): void {work.catch((error: Error)=>{if(this.owner.isActive())this.message=error.message;});}
  build() {
    Column({space:6}) {
      Text('原生输入回归：App 浮层 + 双向列表').fontSize(17)
      Text('子点击='+this.childClicks+' 父释放='+this.parentReleases).fontSize(12)
      Text('下层 DOWN='+this.lowerDowns+' MOVE='+this.lowerMoves+' 滚动='+this.lowerScrolls).fontSize(12)
      Text(this.message).fontSize(12).maxLines(2)
      Row({space:6}) {
        Button(this.contentOwnsTap?'点击归内容':'父 Tap 模式').fontSize(12).onClick(()=>{
          this.contentOwnsTap=!this.contentOwnsTap;this.config.contentOwnsTap=this.contentOwnsTap;
          if(this.control!==undefined)this.run(this.control.updateConfig(this.config));
        })
        Button('计数归零').fontSize(12).onClick(()=>{this.childClicks=0;this.parentReleases=0;this.lowerDowns=0;this.lowerMoves=0;this.lowerScrolls=0;this.record('reset counters');})
        Button('改变宽度').fontSize(12).onClick(()=>this.run(this.resize()))
      }
      Row({space:6}) {
        Button('隐藏').fontSize(12).onClick(()=>{if(this.control!==undefined)this.run(this.control.hide());})
        Button('显示').fontSize(12).onClick(()=>{if(this.control!==undefined)this.run(this.control.show());})
        Button('复位位置').fontSize(12).onClick(()=>{if(this.control!==undefined)this.run(this.control.move(30,340));})
        Button('销毁').fontSize(12).onClick(()=>{if(this.control!==undefined)this.run(this.control.cancel());})
      }
      List({space:8}) {
        ForEach(this.rows,(row: number)=>{
          ListItem() {
            List({space:8}) {
              ForEach(this.columns,(column: number)=>{
                ListItem() {Text('底层 '+row+':'+column).width(140).height(80).textAlign(TextAlign.Center).backgroundColor('#E4E9EF')}
              },(column: number)=>column.toString())
            }.listDirection(Axis.Horizontal).height(80)
              .onScrollStart(()=>{this.lowerScrolls++;console.info('FxInput lower horizontal scroll');})
          }
        },(row: number)=>row.toString())
      }.width('100%').layoutWeight(1)
        .onTouch((event: TouchEvent)=>this.lowerTouch(event))
        .onScrollStart(()=>{this.lowerScrolls++;console.info('FxInput lower vertical scroll');})
    }.width('100%').height('100%').padding(12)
  }
}
