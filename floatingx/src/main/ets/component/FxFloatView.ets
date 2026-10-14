import deviceInfo from '@ohos.deviceInfo';
import { FxScopeSnapshot, FxInteractions, FxScopePlatform } from '../scope/FxScopePlatform';
import { FxSize, FxDisplayMode, FxGestureMode } from '../core/FxTypes';

/** Shared view contract for scope/app/system adapters, preserving one gesture/geometry engine. */
export interface FxFloatViewAdapter {
  interactions: FxInteractions;
  getSnapshot(): FxScopeSnapshot;
  layoutContent(size: FxSize): void;
  handleTouch(event: TouchEvent, observeOnly?: boolean): void;
  canStartPan(event: BaseGestureEvent): boolean;
  handlePan(event: GestureEvent, starting?: boolean): void;
  completeSurfaceTap(): void;
}
let surfaceSequence: number = 0;
@Component
export struct FxFloatView {
  platform: FxFloatViewAdapter = new FxScopePlatform();
  @Prop revision: number = 0;
  private claimedAxis: string = '';
  private surfaceId: string = 'FloatingXSurface_'+(++surfaceSequence).toString();
  private judge(event: BaseGestureEvent, current: GestureRecognizer, others: GestureRecognizer[], touches?: TouchRecognizer[]): GestureJudgeResult {
    if(deviceInfo.sdkApiVersion<20)return GestureJudgeResult.REJECT;
    if(current.getTag()!==this.surfaceId+'x' && current.getTag()!==this.surfaceId+'y')return GestureJudgeResult.CONTINUE;
    if(this.currentSnapshot(this.revision).config.displayMode!==FxDisplayMode.Normal)return GestureJudgeResult.REJECT;
    if(!this.platform.canStartPan(event))return GestureJudgeResult.REJECT;
    if(this.claimedAxis!=='' && this.claimedAxis!==current.getTag())return GestureJudgeResult.REJECT;
    this.claimedAxis=current.getTag();
    // Only a successful axis recognizer takes ownership. Native children receive CANCEL,
    // and pending clicks/page pans cannot later win this same pointer stream.
    for(let i=0;i<others.length;i++) {
      if(others[i].getTag()!==this.surfaceId+'x' && others[i].getTag()!==this.surfaceId+'y')others[i].preventBegin();
    }
    if(touches!==undefined)for(let i=0;i<touches.length;i++) {
      if(touches[i].getEventTargetInfo().getId()!==this.surfaceId)touches[i].cancelTouch();
    }
    return GestureJudgeResult.CONTINUE;
  }
  @Builder
  private content() {
    Stack({ alignContent: Alignment.TopStart }) {
      ContentSlot(this.currentSnapshot(this.revision).content!)
    }
    .onAreaChange((_old: Area, area: Area) => {
      this.platform.layoutContent({width:Number(area.width),height:Number(area.height)});
    })
    .position(this.currentSnapshot(this.revision).projection.contentOffset)
  }
  // Snapshot is adapter-owned, so every ArkUI expression must observe its revision.
  private currentSnapshot(_revision: number): FxScopeSnapshot { return this.platform.getSnapshot(); }
  build() {
    if (this.currentSnapshot(this.revision).content !== undefined) {
      Stack({ alignContent: Alignment.TopStart }) {
        if(this.currentSnapshot(this.revision).config.gestureMode===FxGestureMode.ANDROID_2) {
          Stack({ alignContent: Alignment.TopStart }) {
            Stack({ alignContent: Alignment.TopStart }) { this.content() }
              .width(this.currentSnapshot(this.revision).projection.visibleSize.width)
              .height(this.currentSnapshot(this.revision).projection.visibleSize.height)
              .parallelGesture(PanGesture({direction:PanDirection.Horizontal,distance:this.currentSnapshot(this.revision).config.touchSlopVp!})
                .tag(this.surfaceId+'x')
                .onActionStart((event: GestureEvent) => this.platform.handlePan(event,true))
                .onActionUpdate((event: GestureEvent) => this.platform.handlePan(event)))
              .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, current: GestureRecognizer, others: GestureRecognizer[], touches?: TouchRecognizer[]) => this.judge(_event,current,others,touches))
          }
            .id(this.surfaceId)
            .width(this.currentSnapshot(this.revision).projection.visibleSize.width)
            .height(this.currentSnapshot(this.revision).projection.visibleSize.height)
            .onTouchIntercept((event: TouchEvent) => {
              if(event.type===TouchType.Down){if(event.touches.length<=1)this.claimedAxis='';this.platform.handleTouch(event,true);}
              return HitTestMode.Default;
            })
            .onTouch((event: TouchEvent) => this.platform.handleTouch(event,true))
            .gesture(TapGesture().onAction(() => this.platform.completeSurfaceTap()))
            .parallelGesture(PanGesture({direction:PanDirection.Vertical,distance:this.currentSnapshot(this.revision).config.touchSlopVp!})
              .tag(this.surfaceId+'y')
              .onActionStart((event: GestureEvent) => this.platform.handlePan(event,true))
              .onActionUpdate((event: GestureEvent) => this.platform.handlePan(event)))
            .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, current: GestureRecognizer, others: GestureRecognizer[], touches?: TouchRecognizer[]) => this.judge(_event,current,others,touches))
        } else {
          this.content()
        // A dedicated drag surface consumes clicks only inside the configured region.
        // Child buttons outside it remain native ArkUI controls.
        Stack() {}
          .width(this.platform.interactions.dragArea === undefined ? this.currentSnapshot(this.revision).size.width : this.platform.interactions.dragArea.width)
          .height(this.platform.interactions.dragArea === undefined ? this.currentSnapshot(this.revision).size.height : this.platform.interactions.dragArea.height)
          .position({x:(this.platform.interactions.dragArea === undefined ? 0:this.platform.interactions.dragArea.x)+this.currentSnapshot(this.revision).projection.contentOffset.x,
            y:(this.platform.interactions.dragArea === undefined ? 0:this.platform.interactions.dragArea.y)+this.currentSnapshot(this.revision).projection.contentOffset.y})
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => this.platform.handleTouch(event))
        }
      }
      .width(this.currentSnapshot(this.revision).projection.visibleSize.width)
      .height(this.currentSnapshot(this.revision).projection.visibleSize.height)
      .position(this.currentSnapshot(this.revision).projection.position)
      .clip(true)
      // Android DisplayOnly skips the helper while child controls retain native input.
      .enabled(!this.currentSnapshot(this.revision).config.layoutOnly && (this.currentSnapshot(this.revision).config.gestureMode===FxGestureMode.ANDROID_2 || this.currentSnapshot(this.revision).config.displayMode !== FxDisplayMode.DisplayOnly))
      .opacity(this.currentSnapshot(this.revision).opacity)
      .visibility(this.currentSnapshot(this.revision).visible && !this.currentSnapshot(this.revision).config.layoutOnly ? Visibility.Visible:Visibility.Hidden)
      .hitTestBehavior(this.currentSnapshot(this.revision).config.displayMode === FxDisplayMode.DisplayOnly ? HitTestMode.None:HitTestMode.Transparent)
    }
  }
}
