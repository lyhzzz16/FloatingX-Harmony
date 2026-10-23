import { FloatingX, FxWindowHost, FxContent, FxControl, FxConfig, FxBoundaryMode, FxGestureMode,
  FxReleaseDecision, FxTouchPhase, FxTouchSnapshot, FxSafeAreaPolicy } from 'floatingx';
import { DemoPageOwner } from '../entryability/DemoOwner';

class ArbitrationContent {
  record: (value: string) => void;
  touch: (name: string, event: TouchEvent) => void;
  constructor(record: (value: string) => void, touch: (name: string, event: TouchEvent) => void) { this.record = record; this.touch = touch; }
}

@Builder
function arbitrationContent(params: ArbitrationContent) {
  Column({ space: 8 }) {
    Text('蓝区：父拖动 / 多指测试').height(30)
    Button('子按钮').onClick(() => params.record('child click'))
      .onTouch((event: TouchEvent) => params.touch('button', event))
    Text('子长按 500ms 后继续拖动').height(40).backgroundColor('#DDEEDD')
      .onTouch((event: TouchEvent) => params.touch('long', event))
      .gesture(LongPressGesture({ duration: 500 }).onAction(() => params.record('child long SUCCESS'))
        .onActionEnd(() => params.record('child long END')).onActionCancel(() => params.record('child long CANCEL')))
    Scroll() {
      Column() {
        ForEach([0,1,2,3,4,5,6,7,8,9], (row: number) => {
          Text('子滚动 ' + row).height(32).width('100%')
        })
      }
    }.height(90).width('100%').backgroundColor('#F0E0D0')
      .onTouch((event: TouchEvent) => params.touch('scroll', event))
      .onDidScroll((x: number, y: number) => { if (x !== 0 || y !== 0) params.record('child scroll DELTA=' + x + ',' + y); })
      .onScrollStart(() => params.record('child scroll START'))
      .onScrollStop(() => params.record('child scroll STOP'))
    Text('自定义 stopPropagation 区').height(38).backgroundColor('#E0D0F0')
      .onTouch((event: TouchEvent) => { event.stopPropagation(); params.touch('custom', event); })
  }.width(280).height(300).backgroundColor('#C8E3FF').padding(8)
    .onTouch((event: TouchEvent) => params.touch('root', event))
}

/** 只记录真实分发结果，不将当前实现的输出当作 Android 预期。 */
@Component
export struct ArbitrationDemo {
  @LocalStorageLink('fxHostReady') @Watch('hostReady') private ready: boolean = false;
  @State private message: string = '等待宿主';
  @State private parentDrags: number = 0;
  @State private parentReleases: number = 0;
  private owner: DemoPageOwner = new DemoPageOwner();
  private control?: FxControl<ArbitrationContent>;
  private sequence: number = 0;
  @State private mode: number = 0;
  private childStartY: number = 0;
  private childPointer: number = -1;
  private hideTimer: number = -1;
  aboutToAppear(): void { this.owner.activate(); this.hostReady(); }
  aboutToDisappear(): void { clearTimeout(this.hideTimer); this.run(this.owner.close()); }
  private hostReady(): void {
    if (!this.ready || !this.owner.isActive() || this.control) return;
    const host = this.getUIContext().getSharedLocalStorage()?.get<FxWindowHost>('fxWindowHost');
    if (!host?.isValid()) return;
    const control = FloatingX.installApp({ tag: 'arbitration-probe', host,
      content: new FxContent(wrapBuilder(arbitrationContent), new ArbitrationContent(value => this.record(value), (name, event) => this.childTouch(name, event)), { width: 280, height: 300 }),
      config: new FxConfig({ boundaryMode: FxBoundaryMode.ANDROID_2, gestureMode: FxGestureMode.ANDROID_2,
        contentOwnsTap: true, adsorb: false, position: { x: 25, y: 300 }, safeAreaPolicy: FxSafeAreaPolicy.HOST }),
      interactions: {
        onDown: () => { this.sequence++; this.record('helper DOWN'); },
        onTouch: (event: FxTouchSnapshot) => {
          if (event.phase !== FxTouchPhase.MOVE) this.record('parent ' + event.phase + ' pointer=' + event.pointerId);
        },
        onDrag: () => { this.parentDrags++; },
        onRelease: (event: FxTouchSnapshot) => { this.parentReleases++; this.record('parent RELEASE phase=' + event.phase + ' pointer=' + event.pointerId + ' pos=' + event.position.x + ',' + event.position.y); return FxReleaseDecision.DEFAULT; }
      }
    });
    if (!this.owner.hold(control)) return;
    this.control = control; this.run(control.show());
  }
  private childTouch(name: string, event: TouchEvent): void {
    const changed = event.changedTouches[0];
    console.info('FxArbitration seq=' + this.sequence + ' raw ' + name + ' type=' + event.type + ' time=' + event.timestamp +
      ' changed=' + event.changedTouches.map(t => t.id + ':' + t.windowX + ',' + t.windowY).join(';') +
      ' touches=' + event.touches.map(t => t.id + ':' + t.windowX + ',' + t.windowY).join(';'));
    if (name === 'root' || changed === undefined) return;
    if (event.type === TouchType.Down && this.childPointer < 0) {
      this.childPointer = changed.id; this.childStartY = changed.windowY;
      if (this.mode > 0) { this.control?.requestDisallowInterceptTouchEvent(true); this.record('child DISALLOW'); }
    }
    // 60vp is only a Demo trigger for revocation, not a library gesture threshold.
    if (event.type === TouchType.Move && this.mode === 2 && changed.id === this.childPointer &&
      Math.abs(changed.windowY - this.childStartY) >= 60) {
      this.control?.requestDisallowInterceptTouchEvent(false); this.record('child ALLOW');
    }
    if (event.type === TouchType.Cancel || event.type === TouchType.Up && changed.id === this.childPointer) this.childPointer = -1;
  }
  private record(value: string): void {
    if (!this.owner.isActive()) return;
    this.message = value;
    console.info('FxArbitration seq=' + this.sequence + ' ' + value);
  }
  private run(work: Promise<void>): void { work.catch((error: Error) => this.record('ERROR ' + error.message)); }
  build() {
    Column({ space: 8 }) {
      Text('父子 / 多指仲裁探针').fontSize(18)
      Text('父拖动=' + this.parentDrags + ' 父释放=' + this.parentReleases)
      Text(this.message).maxLines(2)
      Row({ space: 4 }) {
        Button('默认').onClick(() => { this.mode = 0; this.childPointer = -1; this.record('MODE default'); })
        Button('禁止父拦截').onClick(() => { this.mode = 1; this.childPointer = -1; this.record('MODE disallow'); })
        Button('移动后归还').onClick(() => { this.mode = 2; this.childPointer = -1; this.record('MODE revoke'); })
      }
      Text('当前模式：' + ['默认', '禁止父拦截', '移动60vp后归还'][this.mode]).fontSize(13)
      Button('复位').onClick(() => {
        this.parentDrags = 0; this.parentReleases = 0; this.childPointer = -1; this.record('RESET');
        if (this.control) { this.run(this.control.move(25, 300)); this.run(this.control.show()); }
      })
      Button('3秒后隐藏；再点复位恢复').onClick(() => {
        clearTimeout(this.hideTimer); this.record('HIDE armed');
        this.hideTimer = setTimeout(() => { if (this.control) this.run(this.control.hide()); this.record('HIDDEN'); }, 3000);
      })
      Text('操作浮窗内按钮、长按区、滚动区；日志标签 FxArbitration。').fontSize(13)
      Blank()
    }.width('100%').height('100%').padding(12)
  }
}