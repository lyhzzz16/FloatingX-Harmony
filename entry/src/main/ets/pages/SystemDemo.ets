import common from '@ohos.app.ability.common';
import { FloatingX, FxWindowHost, FxContent, FxControl, FxConfig, FxBoundaryMode, FxGestureMode, FxFocusPolicy, FxReleaseDecision, FxDisplayMode, FxSystemFallback } from 'floatingx';
import { DemoOwner, DemoPageOwner } from '../entryability/DemoOwner';
class SystemContentParams {width: number;close: () => void;constructor(close: () => void,width: number = 220) {this.width=width;this.close=close;}}
@Builder
function systemContent(params: SystemContentParams) {
  Column() {Text('系统浮窗：按钮也可起拖').height(40);Button('关闭').onClick(params.close)}.width(params.width).height(90).backgroundColor('#FFEACA').borderRadius(12)
}
@Component
export struct SystemDemo {
  @State private message: string = '商业 HarmonyOS V5 限批准的 2in1 场景；手机/平板系统权限未验收';
  private pageOwner: DemoPageOwner = new DemoPageOwner();
  @State private consumed: boolean = false;
  private wide: boolean = false;
  private control?: FxControl<SystemContentParams>;
  private open(allowFallback: boolean): Promise<void> {
    return this.pageOwner.replace([() => this.createSystemControl(allowFallback)],
      (controls: FxControl<SystemContentParams>[]) => {this.control=controls[0];});
  }
  private createSystemControl(allowFallback: boolean): FxControl<SystemContentParams> {
    let fallback: FxSystemFallback | undefined;
    if(allowFallback) {
      const host=this.getUIContext().getSharedLocalStorage()?.get<FxWindowHost>('fxWindowHost');
      if(host===undefined)throw new Error('显式 app 降级需要已加载的 WindowHost');
      fallback={host:host,pagePolicy:{mode:'blacklist',names:[]}};
    }
    // README system snippet. Context alone suffices when fallback is omitted.
    const control=FloatingX.installSystem({tag:'system-demo',
      context:this.getUIContext().getHostContext() as common.UIAbilityContext,
      content:new FxContent(wrapBuilder(systemContent),new SystemContentParams(() => {if(this.control!==undefined)this.run(this.control.cancel());}),{width:220,height:90}),
      size:{width:220,height:90},config:new FxConfig({boundaryMode:FxBoundaryMode.ANDROID_2,gestureMode:FxGestureMode.ANDROID_2,touchSlopVp:8,focusPolicy:FxFocusPolicy.NON_FOCUSABLE,halfHide:true,position:{x:20,y:100},adsorb:false}),
      fallback:fallback,interactions:{
        onTouch:(event) => {if(this.pageOwner.isActive())this.message=event.phase+' delta='+event.delta.x.toFixed(1)+','+event.delta.y.toFixed(1);},
        onRelease:() => this.consumed?FxReleaseDecision.CONSUMED:FxReleaseDecision.DEFAULT},
      events:(event) => {if(this.pageOwner.isActive())this.message='actualScope='+event.actualScope+(event.error===undefined?'':'; '+event.error.code+': '+event.error.message);}});
    this.getUIContext().getSharedLocalStorage()?.get<DemoOwner>('fxSystemOwner')?.add(control);
    return control;
  }
  aboutToAppear(): void {this.pageOwner.activate();}
  private async resize(): Promise<void> {
    const control=this.control;if(control===undefined)return;
    this.wide=!this.wide;
    const value=await control.updateContentAndWaitForLayout(new SystemContentParams(() => {this.run(control.cancel());},this.wide?280:220));
    if(this.pageOwner.isActive())this.message='layout='+value.layoutVersion+' width='+value.content.width+' requestX='+value.requestedPosition.x+' actualX='+value.position.x;
  }
  aboutToDisappear(): void {this.run(this.pageOwner.close());}
  private run(promise: Promise<void>): void {promise.catch((error: Error) => {if(this.pageOwner.isActive())this.message=error.message;});}
  build() {Column({space:12}) {
    Text(this.message)
        Button(this.consumed?'接管释放：开':'接管释放：关').onClick(() => {this.consumed=!this.consumed;})
        Button('更新宽度并等待布局').onClick(() => this.run(this.resize()))
    Button('显示系统浮窗（不降级）').onClick(() => this.run(this.open(false)))
    Button('权限/能力失败时显式 app 降级').onClick(() => this.run(this.open(true)))
    Button('DisplayOnly：跨应用透传验收').onClick(() => {if(this.control!==undefined)this.run(this.control.updateConfig(new FxConfig({displayMode:FxDisplayMode.DisplayOnly})));})
    Button('隐藏（保留窗口）').onClick(() => {if(this.control!==undefined)this.run(this.control.hide());})
    Button('重新显示').onClick(() => {if(this.control!==undefined)this.run(this.control.show());})
    Button('关闭并销毁').onClick(() => {if(this.control!==undefined)this.run(this.control.cancel());})
  }.width('100%').padding(16)}
}
