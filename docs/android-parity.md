# Android 2.3.7 对齐审计与 API 契约

## 基线与范围

- Android：FloatingX **2.3.7**，tag `2.3.7`，commit `a4b9dbfc1649accde832d2f70dd90d54bf5fac9a`。
- Harmony：上游与本 fork 的 `731e834245492c8b43256de861208ed2abfe1c0c`。
- 本预览版：`0.1.1-yb.4`。不宣称所有 Android API、默认值、窗口类型和设备表现均已完全相同。
- 本轮修正父/子手势、释放回调和系统窗口异步移动；见 [.4 手势审计](gesture-round3.md)。初始化/尺寸变化、安全区、窗口生命周期、焦点与隐藏测量的历史 C01～C25 记录见 [.2/.3 对齐记录](parity-round2.md)。不包含业务状态、倒计时、导航、录音或窗口切换策略。

## 逐项证据与取舍

| 变更 | Android 源码依据 | Harmony 映射与边界 |
| --- | --- | --- |
| Down/Move/Up/Cancel 快照 | [IFxTouchListener](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/listener/IFxTouchListener.kt)、[FxViewTouchHelper](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)：onDown/onDragIng/onUp，MotionEvent 区分动作，记录主触点及 raw 坐标 | `interactions.onTouch`。补充明确的取消原因。ANDROID_2 区分父/子归属；父收到 POINTER_UP 也终止 helper，子次指抬起不触发父释放；静止不推断 Up；生命周期取消只通知，不触发释放策略 |
| 释放前接管 | [getManagerView](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/imp/FxBasisControlImp.kt) 暴露原生容器；[FxBasicContainerView.onTouchEvent](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt) 才进入库手势处理；[AOSP View](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-15.0.0_r1/core/java/android/view/View.java#L16429-L16448) 中原生 OnTouchListener 返回 true 时不再调用 onTouchEvent | `onRelease` 返回 DEFAULT/CONSUMED，是 ArkUI 对原生容器事件接管能力的适配，不是假称 Android 有同名接口。只接管本次释放的默认吸附/回弹/存储/浮窗点击，不撤销已发生的拖动或长按 |
| Android 拖动边界 | [safeX/safeY 与 updateMoveBoundary](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewLocationHelper.kt)、[setEnableScrollOutsideScreen](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/assist/helper/FxBasisHelper.kt) | 显式 `boundaryMode: ANDROID_2`。保持原默认 CONTENT；不增加无证据的四边无限出屏模式 |
| 关闭吸附后释放不强制归位 | [touchCancel](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)：仅 enableEdgeAdsorption 为真时调用 moveToEdge | ANDROID_2 下 `adsorb:false` 保留拖动结束位置；正常未消费释放仍可保存位置 |
| 实测几何、布局通知 | [getView/getManagerView/getX/getY](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/imp/FxBasisControlImp.kt)、[onSizeChanged/onLayout](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt) | ArkUI 不暴露 Android View，改为副本快照、布局订阅及 `updateContentAndWaitForLayout`；System 额外报告原生实际位置，这是平台适配信息 |
| 取消等待及旧操作失效 | Android View 布局/触摸跟随实例和挂载生命周期；[onPreCancel](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt) 交给 helpers 终止工作 | Promise、原生窗口事务均绑定原实例；销毁/隐藏/替换使旧结果失效。属于异步平台必要约束，不增加业务所有权规则 |

**不能误读 Android 回调顺序**：`IFxTouchListener.onTouch` 位于库的默认处理之后；`touchCancel` 先 `moveToEdge`，再 `onUp`，最后处理点击。需要在默认行为前接管时，对应的是原生 `View.OnTouchListener`，不是该同名接口。Harmony 新增观察与决策回调的顺序如下。

## 触摸、释放与重入

`FxInteractions` 的 `onDown` / `onUp` 在 ANDROID_2 提供 helper 初始化和默认父终止通知。`onTouch` 仅观察，`onRelease` 是同步决策扩展：

```ts
onDown?: (event: FxTouchSnapshot) => void | Promise<void>;
onTouch?: (event: FxTouchSnapshot) => void | Promise<void>;
onRelease?: (event: FxTouchSnapshot) => FxReleaseDecision;
onUp?: (event: FxTouchSnapshot) => void | Promise<void>;
```

- ANDROID_2：helper 初始化 → `onDown` → DOWN 观察；父 MOVE 更新后通知拖动；终止时 `onRelease` 决策 → 默认结算启动 → `onUp` → 库点击/长按 → 终止观察。`onUp.position` 为最后处理的 MOVE，不采用 UP 坐标。异步窗口结算不保证在 `onUp` 前呈现到屏幕。
- `onTouch` 可观察到子序列 UP，它不代表父 `onUp`。子序列终止没有父释放；原生表面 Tap 的 App/Scope 适配及真实归属边界见 [.4 审计](gesture-round3.md)。System 不额外合成空白 Tap 父处理。
- 父收到真实输入 CANCEL 或 POINTER_UP 进入终止；如仍有点击候选，CANCEL 也按 Android 处理时钟分类。子输入 CANCEL 仅观察。父 helper 因 POINTER_UP 复位后，随后实际收到的 UP 仍可再次通知父终止，不能当成重复事件丢弃。
- 隐藏/销毁/宿主改变/配置改变/主动移动等生命周期打断，仅发送带原因的 CANCEL，不执行用户释放/点击/吸附。内容测量调整按现有 ANDROID_2 resize 契约保留手势。
- CONSUMED 跳过本次默认吸附、回弹、保存、`onUp` 和浮窗点击；它不能撤销已经处理的 MOVE。System 会完成最后已处理位置，旧确认不会覆盖调用方在回调中新发起的移动。调用方自行处理异步 Promise 失败。
- 决策必须同步返回枚举；异常报告回调失败并走默认路径。异步观察不阻塞手势。回调重入隐藏/移动/取消时，旧流程代际失效，不继续执行旧默认行为。
- LEGACY 保留原顺序与行为：终止观察 → 释放决策 → 默认点击/拖动结束；仅匹配主触点 UP 结束，输入 CANCEL 不分类点击。新增 `onDown` / `onUp` 不改变 LEGACY 路径。
- `delta` 是原始触点累计位移；`position` 是边界处理后的逻辑浮窗坐标，尚未执行释放后的吸边。System 窗口确认几何与待提交逻辑位置分别维护。

`ANDROID_2` 省略 `touchSlopVp` 时从所属 UIContext 获取 Pan 默认距离；显式正有限值优先。这是平台参数适配，不能保证不同 OS 数值相同。DisplayOnly 只禁用库 helper，不禁用原生子内容；隐藏准备请使用 layoutOnly。完整原生分发、长按、任意内容、真实多指仍有待验证或待实现的边界，见 [.4 审计](gesture-round3.md)。

## Android 边界模式

```ts
new FxConfig({
  boundaryMode: FxBoundaryMode.ANDROID_2,
  halfHide: true, halfHideRatio: 0.5,
  rebound: true, adsorb: false
});
```

令宿主宽高为 W/H，内容宽高为 w/h，比例为 r，顶部/底部系统安全区为 t/b：

| 设置 | 拖动中 X 范围 | 拖动中 Y 范围 |
| --- | --- | --- |
| halfHide=false，rebound=true | 0 .. W-w | t .. H-h-b |
| halfHide=true，rebound=true | -w*r .. W-w*r | t .. H-h-b |

最终边界在非半隐藏时叠加四边 margin；半隐藏时仅叠加上下 margin。rebound=false 拖动中也采用最终边界。Android `edgeOffset` 没有新增为独立参数，等价值由调用方合入 margin。此模式的 rebound 对应 Android `enableEdgeRebound`（允许拖动越过 margin），同时保留既有回弹动画开关用途。

注意 Android 源码右边界确实是 **W-w*r**：r≠0.5 时左右可见比例不对称，本 fork 忠实保留公式。HOST/EXTEND 不额外加入水平 inset；显式 AVOID_SYSTEM 将公式映射到权威安全矩形，投影也裁剪到该区域。已有 oversized 内容的 leading-edge 容错保留，不宣称它与 Android 反向边界异常情况等价。

App/Scope 使用宿主裁剪、按逻辑位置计算可见投影。System 将可见片段映射为非负窗口及内容偏移，再读取窗口实际矩形；零可见尺寸返回能力错误，不报告伪成功。系统拒绝移动、修正尺寸、权限限制都不等同于 App 能力。

这并非四边自由越界：Android 此配置仍约束 Y，普通模式也限制 X。ANDROID_2 初始化按完整内容九宫格再夹紧；resize 保持绝对坐标，开启吸附时按旧内容中心选择原侧。原 CONTENT 算法及动画曲线保留。

## 几何与布局完成

- `control.getGeometrySnapshot()`：副本，包含 instanceId、layoutVersion、measured、coordinateSpace、density、viewport/insets、content、requestedPosition、position、projection。
- `control.subscribeLayout(listener)`：返回取消订阅函数；通知宿主变化与内容已测量布局，首次可能先出现 measured=false 的声明尺寸；销毁释放订阅。它不是每一帧移动监听。
- `control.updateContentAndWaitForLayout(params)`：要求已挂载且宿主有效，可处于 layoutOnly 的 PREPARED 状态；保留同一个内容节点，等待本次参数更新之后的 measure+layout，并等待 System 投影完成，返回实测快照。包括同尺寸更新，不使用固定毫秒延时。
- 返回时仅保证本次布局及已排队窗口几何已应用，不承诺未来不会发生字号/旋转等新的布局，也不代表屏幕合成帧已经呈现。
- `measured=false` 时 content 仅是创建时声明尺寸；true 表示有过真实原生测量。pending 更新时同步快照仍是最近已知布局，要求新参数对应尺寸应等待上述 Promise。
- 更新替换、隐藏、销毁、宿主卸载时等待拒绝；无可见宿主为 NO_HOST，旧更新为 LAYOUT_SUPERSEDED，主动取消为 LAYOUT_CANCELED，销毁为 DESTROYED，无有效测量为 INVALID_GEOMETRY。多个竞争原因并发时不保证错误优先级。
- 所有公开几何单位均为 vp，native px=vp*density。Scope/App 的逻辑原点是所属宿主；System 为目标显示区域；触点 pointer/startPointer 为 Scope/App 的 window vp、System 的 display vp，`delta` 可跨窗口移动保持稳定。不要将触点绝对值直接当 host-local 浮窗坐标。
- `position` 为最终已知逻辑坐标；System 的 `requestedPosition` 保留本次投影请求，`projection.position/visibleSize/contentOffset` 表示实际可见窗口片段。System 实际矩形被修正时与请求不同，调用方应使用返回值。
- `instanceId` 仅进程内唯一，`layoutVersion` 仅该实例的布局序号，不能作为跨进程持久 ID。

布局底层依据：[OpenHarmony 5.0 FrameNodeBridge::SetNeedsLayout](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-5.0.0-Release/frameworks/bridge/declarative_frontend/engine/jsi/nativeModule/arkts_native_frame_node_bridge.cpp#L1354-L1362) 标记 MEASURE_SELF_AND_PARENT。完成通知在 layout 回调后的微任务执行，并检查本次测量版本，防止旧测量完成新请求。

## 验证范围

核心测试使用真实控制器/几何/适配器逻辑配合原生边界替身；ArkTS 部分由测试环境转译。原生 HAR 与 HAP 构建另行验证 ArkTS 类型/API。

本轮新增回归覆盖：静止配对、多指隔离、系统及生命周期取消、回调重入、消费后不保存、原生移动回读、边界公式、同尺寸布局、旧测量无效、连续更新、隐藏竞争、挂载更新失败。原有内容/子按钮/多实例/生命周期/显式 fallback 测试继续执行。

**构建和单元测试不代表设备验收。** 真机的旋转/分屏/字号/密度、子控件点击、跨应用透传及 System 权限/限制需要逐项验证；不支持的 System 场景明确记录错误，不以显式 App fallback 视作 System 验收通过。操作步骤见 [发布与验收](fork-release-validation.md)。
