# 宿主手势阈值适配与等价性边界

## 状态

已合入 `0.1.1-yb.4`。核心回归、HAR/Demo 构建及独立 Demo 单指冒烟结果见 [验证记录](device-validation.md)。旧 `0.1.1-yb.3` HAR 不包含本页默认值行为。本文只涉及公开组件及平台。

## 选择依据

Android FloatingX 2.3.7 从容器 Context 的 `ViewConfiguration.scaledTouchSlop` 取得 px 阈值。AOSP 从 `config_viewConfigurationTouchSlop` 资源读取，资源覆盖及密度可改变结果，因此单台设备的数值不能作为跨设备常量。Android 拦截 MOVE 使用 `abs(dx)>=slop || abs(dy)>=slop`。

Harmony `PanGestureOptions.getDistance()` 自 API 18 提供，返回 vp。OpenHarmony 6.0 的实现由 Pan 默认配置建立 px 距离，getter 经当前 Pipeline 换算回 vp，因此在所属窗口的 `UIContext.runScopedTask` 内创建及读取。公开实现普通触摸默认为 5vp，但组件不复制这个数字。该接口读取的是 ArkUI Pan 配置，不是触控驱动校准值，也不是 Android `ViewConfiguration` 的同名等价查询。

已核对社区 `@csp/floating-button`：默认 dragThreshold=5，使用 touches[0] 及欧氏距离，原始事件处理只有 Down/Move/Up。它不能直接替换本组件的 Android 轴向阈值与取消链路。原生全向 Pan 同样使用欧氏距离；直接替换会改变对角线起拖边界。API 26 新增的手势收集干预接口不能作为 API 23 的基础实现。

本方案保留 Android 判定规则，以宿主平台配置替代参考机常量；这是平台参数适配，不承诺不同系统的阈值数值相同。没有找到同时覆盖完整 Android 分发边界、可直接复用的更优社区实现；该结论限于本次实际审阅的源码。

## 新源码契约

- `ANDROID_2` 省略 `touchSlopVp` 时，挂载后在所属 UIContext 获取默认值；Scope、App、System 共用现有 Scope 手势引擎。System 使用浮窗内容的 UIContext。
- 原生两个轴向 Pan 和内部 FxTouch 使用同一解析结果。公开单位始终为 vp，不再次乘除屏幕密度。
- 显式正有限数值优先，保留自定义策略与确定性测试能力；不读取平台默认值。没有业务类型、设备型号或调用方白名单。
- LEGACY 默认行为及已有显式配置不变；新默认只作用于 opt-in 的 ANDROID_2。
- 宿主缺失或平台结果非法时明确失败，不静默回退为 5/8vp。解析在修改当前手势状态之前完成。
- 每次 applyConfig 解析，不监听或修改全局系统配置，不引入 KN/C++ 依赖。

```ts
new FxConfig({ gestureMode: FxGestureMode.ANDROID_2 });
```

旧 yb.3 使用方若尚未更新 HAR，应在自己的 UIContext 中读取 `new PanGestureOptions().getDistance()` 后显式传入 `touchSlopVp`，不能直接省略。新包接入后才可移除接入方重复取值。

## 验证与边界

核心回归覆盖不同 UIContext 默认值、轴向恰等边界及对角线反例、显式覆盖、LEGACY 兼容、非法默认值不破坏已有手势；包含在 .4 的 280 项通过结果中。独立 Demo 的 Scope/App/System 示例已去掉固定 8vp。2026-10-14 手指验收 Scope 子按钮点击/起拖、System 前后台拖动及关闭通过。

阈值来源正确不代表原生分发完全等价。多指 Pan 仲裁、真实子目标归属、disallow-intercept、长按及任意嵌入内容仍需独立处理，逐项见 [.4 审计](gesture-round3.md)。父 MOVE、父次指终止及输入 CANCEL 的本轮核心修复不能继续描述为 .3 的旧状态，也不能升级为全量设备证明。

Phone/Pad、多密度、手指/鼠标/笔及系统 Cancel 尚未逐项验收；普通 Pan distance 不代表输入源专用距离已经对齐。

## 公开依据

- [Android FloatingX 2.3.7 helper](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)
- [AOSP ViewConfiguration](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/view/ViewConfiguration.java)
- [Harmony PanGesture 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-gestures-pangesture)
- [OpenHarmony 6.0 JS Pan options/getter](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-6.0-Release/frameworks/bridge/declarative_frontend/jsview/js_gesture.cpp)
- [OpenHarmony 6.0 Pan recognizer](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-6.0-Release/frameworks/core/components_ng/gestures/recognizers/pan_recognizer.cpp)
- [社区 floating-button 源码](https://gitee.com/chenshipeng0914/floating-button/blob/master/floating_button/src/main/ets/components/FloatingButton.ets)