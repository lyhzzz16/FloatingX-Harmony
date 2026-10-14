# 0.1.1-yb.5：原生输入两项回归的最小修复

## 范围与评估

基于 .4 提交 `71e253b`，Android FloatingX 2.3.7 固定 commit `a4b9dbfc1649accde832d2f70dd90d54bf5fac9a`。两项反馈对应真实组件路径：浮窗根 Transparent 允许下面页面从 DOWN 起参与；表面父 Tap 能把仅观察到的子 UP 转成 finishTouch/onRelease。这与 Android 子 View 完整消费点击时不执行父 helper 释放不同。

本次不重写输入分发，不增加内容类型识别、业务命中区域或应用状态；不修改 CMP 框架，不合成第二条输入流。只改 FxConfig、FxFloatView、FxScopePlatform 三个生产文件；其余为回归测试、独立示例、版本及文档。

## 修复与证据

### 可见范围隔离

ANDROID_2 正常/仅点击模式的浮窗根改用 API20 `HitTestMode.BLOCK_HIERARCHY`。位置、宽高仍直接使用当前 projection 的可见片段；全屏 App 父层继续 Transparent。不增加遮住子按钮的覆盖层。

[官方命中控制文档](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-hit-test-behavior.md)说明该模式保留自身和子节点命中，阻断较低优先级的兄弟和父节点。进一步核对 [OpenHarmony 6.0 FrameNode::TouchTest](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-6.0-Release/frameworks/core/components_ng/base/frame_node.cpp#L3168-L3215)：子返回 BLOCK_HIERARCHY 后，父层停止遍历，并将该结果继续向上传递，不因父是 Transparent 而恢复命中。这是采用该模式的源码依据；设备结果另列，不能仅凭枚举断言验收成功。

ANDROID_2 激活仍明确拒绝 API<20；枚举读取另有版本保护。LEGACY 原路径、DisplayOnly 的 None/子交互约定、隐藏和 layoutOnly 不变。这里保证正常可见浮窗区域的输入隔离，不把 DisplayOnly 改成新的阻断语义。

### 内容显式拥有普通点击

新增 `FxConfigOptions.contentOwnsTap?: boolean`，默认 false。true 要求 gestureMode.ANDROID_2，否则 INVALID_CONFIG；copy/updateConfig 均保留并校验。

```ts
new FxConfig({
  gestureMode: FxGestureMode.ANDROID_2,
  boundaryMode: FxBoundaryMode.ANDROID_2,
  contentOwnsTap: true
});
```

true 表示整个内容区域的普通点击由内容负责：

- 父 Tap 使用独立 tag，在原生仲裁入口直接 REJECT；不等父 Tap 成功后才忽略回调。子手势与父横/纵 Pan 不受该拒绝分支影响。
- 仅观察且父尚未接管的 UP/CANCEL 继续发 onTouch，随后清理，不创建 pendingTap，不调用父 onRelease/onUp/settle/库 click。
- completeSurfaceTap 在入队前和执行时再次检查配置/代际。修正旧微任务先清理 pendingTap 后才校验代际的问题，防止误清新序列。
- 真正获胜的父 Pan 仍取消子触摸、保留父终止接收器，沿用 onRelease/CONSUMED 契约；即便只完成接管、尚无后续 MOVE，父释放仍发生，不以 dragged=false 全部过滤。
- hide/destroy/config-change 继续清理指针、归属、pendingTap 和旧代际。不会改变其他实例。

默认 false 保留原父表面 Tap 路径，便于父自有普通点击的旧使用方兼容；并不声称该默认模式能自动判断所有嵌入子内容是否消费。

Android 对照：[FxBasicContainerView 119–126](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt#L119-L126)区分拦截与父触摸入口；[FxViewTouchHelper 36–73、117–145](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)区分子终止复位、父终止及点击候选。contentOwnsTap 是 Harmony 缺少真实 childResult 时的显式宿主契约，不宣称 Android 有同名 API。

## 通用性边界

该开关不自动识别 CMP/ArkUI 是否消费，也不保证任意子框架的取消链。若同一内容要求“按钮归子、未消费空白归父”，必须由宿主提供真实归属或明确分区；不能凭是否移动、是否存在 onClick 或按钮坐标猜测。

CMP 取消沿用本轮排除范围，不修改、不验收；原生 ArkUI 验证不能代替真实 CMP/XComponent。原有多指仲裁、disallow-intercept 和库级原生长按缺口仍见 [.4 审计](gesture-round3.md)。消费方采用新模式需显式传 true，并继续处理观察 UP/CANCEL 的按住态清理；仅换包不会自动启用该点击契约。

## 验证

- 288/288 核心测试通过，无跳过；最终独立 HAR 和 Demo HAP 构建通过。ArkUI 策略方法测试执行生产方法，但不模拟原生命中树，因此不用于宣称底层隔离通过。
- 旧 .4 对照：内容点击出现1次父 release（期望0）；旧/新 Tap 同时排队时得到0次 release（期望新序列1次）。.5 分别为0和1。
- 回归覆盖显式配置校验/copy、子 tap/轻微抖动/Cancel 仅观察、真实 Pan 无 MOVE 也释放、CONSUMED 保留、hide/destroy/config-change 旧任务失效、旧微任务不清新序列、Tap 提前拒绝不取消子、Pan 取消子且保留父终止、API20 保护与旧模式。
- 新增独立“输入回归”页：App 浮层位于原生纵向列表/横向列表上方，记录子点击、父释放、下层 DOWN/MOVE/滚动数；可以切换点击归属、隐藏、改变宽度和位置。没有引入业务代码或 CMP 依赖。
- 2026-10-14 手指反馈正常：A/B 点按、按钮/文字起拖、浮窗外列表滑动。日志与补充原生 UI 测试的分层结果见 [设备记录](device-validation.md)。完整业务/CMP 验收仍需消费方换包后进行。

当前是 debug 预览 HAR；包内 manifest 记录源码 commit、SDK、版本与 SHA256。公开交付仅含 HAR、未签名 Demo、源码及文档；开发签名和原始设备日志不分发。
