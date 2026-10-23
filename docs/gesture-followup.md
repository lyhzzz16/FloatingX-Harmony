# 父子手势修复与多指验收（2026-10-23）

## 当前结论

本记录对应 0.2.0 发布前、基于 ca1d39b 的设备验收；正式发布不自动升级消费工程。修复了成功长按的终止回调丢失，补充了子内容请求禁止父拦截的接口；不宣称已完整复刻 Android 对任意已成功子手势的 CANCEL 分发。

## Android 的真实基准

基准是 FloatingX 2.3.7：a4b9dbfc1649accde832d2f70dd90d54bf5fac9a。

- `FxBasicContainerView` 继承 Android FrameLayout。`onInterceptTouchEvent` 调用 `FxViewTouchHelper.interceptTouchEvent`；子 View 的 `requestDisallowInterceptTouchEvent` 由原生 ViewGroup 处理，库没有重写该规则。
- 首指任一轴移动达到系统 touchSlop，才允许父拦截。子内容如果提前请求禁止，父不接管；撤销后，后续 MOVE 重新判断，沿用原 DOWN 起点。
- Android 父接管子输入时，ViewGroup 给子目标发送 ACTION_CANCEL。这与“只让子按钮不再点击”不同，也不能拿长按自然 END 代替即时 CANCEL。
- 父已接管时，`touchEvent` 按 actionMasked 把任一 POINTER_UP、UP、CANCEL 都交给 `touchCancel`，随后 `performClickAction` 清除主指。因此，松开任一指后，剩余指不会自动继续拖；后续 UP 仍可能再次通知 onUp。这是 2.3.7 行为，不额外设计主指自动切换。

## 问题一：成功长按后没有终止回调

现有 `FxFloatView.judge` 对所有其他识别器无条件调用 preventBegin。

OpenHarmony 6.0 Release 和 master 的 JS 绑定都直接调用 SetPreventBegin(true)，没有检查成功状态；识别器后续 HandleEvent 会在这个标志为 true 时提前返回。这解释了为何成功长按接管后收不到 UP，也收不到 END。

修复只对尚未成功/失败的识别器调用 preventBegin，保留已经成功识别器的自然终止。没有调用业务回调，没有关闭长按，没有添加录音笔判断。

边界：TouchRecognizer.cancelTouch 的收集目标排除了 GestureRecognizer，实际只取消对应原始触摸接收器。当前公开 GestureRecognizer API 没有直接终止已成功识别器的方法；setEnabled(false) 是抑制回调，不是取消。因而这次恢复 END，仍不能宣称实现了 Android 接管瞬间的子手势 CANCEL。

## 问题二：子内容不能请求禁止父拦截

新增与 Android 同名的同步方法：

```ts
control.requestDisallowInterceptTouchEvent(true);
// 同一触摸序列需要归还时：
control.requestDisallowInterceptTouchEvent(false);
```

- 在子内容 DOWN 或父尚未接管时调用；当前只作用于 ANDROID_2 模式。
- 状态由每个浮窗自己的手势引擎持有，不使用全局标志，不影响其他浮窗。
- 最后一指 UP、CANCEL、隐藏、销毁及宿主中断清除状态。未开始触摸和父已接管后的请求不改变当前归属。
- 禁止期间保留原生并行 Pan 识别，但不移动父、不取消子输入。不能直接 REJECT 父识别器，否则该序列后续撤销禁止也无法恢复。
- 撤销后，由下一次移动决定是否接管，沿用原触点起点，不补发 DOWN。
- 不默认规定 Scroll 永远优先；子内容需要通过自己的触摸/手势策略明确提出请求。stopPropagation 不等于禁止父拦截。
- 已成功 Scroll/长按在撤销后的即时取消仍受上一项平台边界约束，不能泛化子按钮验收结果。

## 修改范围

- `FxFloatView.ets`：成功识别器保护；禁止期间保留候选 Pan；撤销后接管；清除临时识别器引用。
- `FxScopePlatform.ets`：每实例的禁止拦截标志及序列/生命周期复位。
- `FloatingX.ets`、`FxController.ts`、`FxPlatform.ts`：公开句柄及同步转发。
- `FxAppPlatform.ets`、`FxSystemPlatform.ts`、`FxNativeWindow.ts`、`FxWindowAdapter.ets`：App/Scope/原生 System 复用同一个引擎，无业务策略。
- `ArbitrationDemo.ets`：默认、禁止父拦截、移动后归还三种模式；记录原始指针、列表实际滚动、长按终止；提供延迟隐藏测试。60vp 仅为 Demo 主动撤销的触发条件，不进入库阈值。
- 三个宿主测试文件：验证成功识别器保护、禁止/撤销、窗口和触摸序列隔离。

不修改安卓、DTMP、CMP 框架、录音笔业务、系统安全区或长按触觉反馈；系统浮窗 CMP 问题继续挂起。

## 已获得的验证

- 宿主测试：293 项通过，新增 3 项。测试替换了原生 SDK 边界，不能代替真机分发。
- DevEco Run：12:35:17 构建成功（2.304 秒），12:35:18 安装并启动独立 Demo；未从终端启动 Harmony 构建，未执行清理。
- 真机：Mate 80 Pro Max / HarmonyOS 7.0.0 API 26。原始日志由维护者本地留存；公开仓库仅保留以下验收摘要。
- seq=1，12:36:12–16：默认模式长按成功后拖动；父释放后子收到 END。用户确认操作正常。缺失终止回调修复通过；即时 CANCEL 仍不通过。
- seq=2–4，12:36:26–30：禁止父拦截模式，Scroll 有真实 DELTA，父没有 RELEASE；用户确认列表滚动、浮窗不动。
- seq=5–7，12:36:41–49：移动后归还模式，DISALLOW → ALLOW → 子原始触摸 CANCEL → 父 RELEASE，没有子按钮 click；用户确认正常。
- 多指首指静止：用户确认仅第二指移动时浮窗不动；seq=16（12:39:18–23）没有父 RELEASE。
- 多指拖动后先松第二指：用户确认剩余首指停止拖动；seq=17（12:39:48–52）两次 RELEASE 位置完全相同。
- 多指拖动后先松首指：用户确认第二指不能接续拖动。以上两种抬指顺序均符合 Android 2.3.7 的 POINTER_UP 复位行为，并非需要修复的自动换指缺失。
- 跨子按钮/标题区双指拖动：用户确认没有误触发子按钮点击；该轮日志也没有 child click。多次重复操作没有逐项唯一编号，不将其强行绑定到单个 seq。
- 双指按住后隐藏：seq=21 在 12:41:22.985 收到 parent cancel；复位后 seq=22 新单指正常拖动并释放，用户确认正常。

上述结果仅覆盖这些具体操作。尚未覆盖第二指先触发原生 Pan 判断后首指才移动、三指、已成功 Scroll 撤销禁止后的即时取消，以及 Android 真机的同操作事件对照。成功子手势的即时 CANCEL 缺口仍未闭环，不应发布为“全面等价 Android”。

## 公开源码依据

- [Android 2.3.7 FxViewTouchHelper](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)
- [Android 2.3.7 FxBasicContainerView](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt)
- [OpenHarmony 6.0 JS 手势绑定](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-6.0-Release/frameworks/bridge/declarative_frontend/engine/functions/js_gesture_recognizer.cpp)
- [OpenHarmony 6.0 触摸取消](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-6.0-Release/frameworks/core/common/event_manager.cpp)
- [官方手势公共接口](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-gesture-common.md)

公开源码不等于本机系统二进制；根因判断同时依据修改前后同机复现结果。