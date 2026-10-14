# 0.1.1-yb.6：透明预布局与绘制驱动验证

## 改动和 Android 依据

仅修改共享 FxFloatView 的预布局呈现/交互策略及 FxConfig 注释。App、Scope、System 使用同一视图；没有业务依赖、CMP 依赖、尺寸规则或新增开关。

Android FloatingX 2.3.7 固定提交 `a4b9dbfc1649accde832d2f70dd90d54bf5fac9a`：
[FxBasicContainerView.initView / onLayout](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt#L51-L115)先 INVISIBLE，首次布局及 helpers 初始化后 VISIBLE。对齐目标是布局/定位完成后展示，不要求不同平台使用同名属性。

| 状态 | 呈现 | 输入/无障碍 |
| --- | --- | --- |
| snapshot.visible=false | Hidden | 根不参与命中，识别器拒绝；沿用隐藏语义 |
| visible=true、layoutOnly=true | Visible，最终 opacity 强制 0 | enabled=false，根 None，识别器拒绝，no-hide-descendants；System 原生禁触摸/焦点保持 |
| visible=true、layoutOnly=false | 原 snapshot.opacity | 恢复原手势模式、点击归属和命中规则 |

固定透明优先于动画中的 snapshot.opacity；不引入极小透明度、屏幕外定位、固定延时或固定最终尺寸。边界/吸边/坐标/手势分发与取消算法保持原样。

## 不变的 API 契约

- `layoutOnly` 是内容已挂载、最终呈现与交互关闭、允许内部绘制推进布局的准备态。它不承诺任意渲染后端在透明时一定绘制。
- `isShow()` 在预布局期间仍为 false，状态为 PREPARED。
- **SHOW 仍是原生命周期事件，不是用户曝光事件。** PREPARED 可以发 SHOW；`updateConfig(layoutOnly=false)` 不额外发 SHOW。本轮没有更改事件协议。
- `updateContentAndWaitForLayout()` 等待本次更新的原生测量/布局，包括同尺寸的新 revision，并等待 System 几何提交。它不识别“非零占位”和“渲染器最终尺寸”。
- 内容准备完成信号由内容提供者负责。对绘制驱动内容，收到真实尺寸后再更新参数、等待布局、定位、最后退出 layoutOnly；不能仅凭 show() 成功或 measured=true 宣告内容准备完成。
- App/Scope 宿主尚未就绪时 show() 可先接收显示意图；等待真正挂载/SHOW 后才调用布局等待接口。不要把 SHOW 当曝光，也不要强制把“请求已接收”改成“已绘制”。
- hide/cancel/宿主销毁、旧 revision 失效、System 非焦点策略和窗口矩形确认逻辑均保持原样。

## 通用真机夹具

独立 Demo 的“绘制布局”页使用 `NodeController.makeNode(windowUIContext)` 创建 FrameNode 与 RenderNode；尺寸初始为非零 1×1。确认进入 PREPARED 后请求重绘，只有系统调用 `RenderNode.draw()` 才计算并返回尺寸。随后通过公开 API 更新内容、等待布局、move、退出预布局。

没有手工调用 draw，没有在 aboutToAppear 或计时器中注入尺寸；5 秒计时器只负责判定缺少 draw。Home 用例由 UIAbility.onBackground 一次性触发，避免后台定时器暂停造成假结果。节点来自目标窗口 UIContext，没有复用主窗口原生节点。

每种宿主全流程包含：首次尺寸 220×112、变大 280×144、同尺寸新 revision、变小 220×112、hide/show 同实例恢复。每轮日志顺序为 `DRAW → LAYOUT → GEOMETRY → PRESENT`，DRAW 时 `isShow=false`，PRESENT 时 `isShow=true`。实际 vp 尺寸允许像素取整误差。

额外按钮：

- 透明停留：保持 App PREPARED，验证画面不可见、覆盖区域的底层按钮可点击。
- Hidden 对照：同一夹具额外隐藏内容子树，观察该后端是否仍能收到 draw；**不把此按钮标为旧版故障复现**。
- Home 后系统首显：先点击再按 Home，后台事件启动 System 全流程；桌面浮窗的“浮窗更新”可继续触发绘制更新。

## 2026-10-15 验证结果

SGT-AL10 / API26，独立开发签名 Demo，非 CMP 后端。设备日志时钟与主机不一致，以下时刻用于日志定位，不作为用户本地时间：

| 范围 | 结果和证据 |
| --- | --- |
| 核心回归 | 290/290 通过，无跳过，含 TypeScript 编译。新覆盖隐藏/预布局拒绝识别、不取消子识别器、不阻断底层；退出恢复各模式；SHOW 兼容语义 |
| 旧策略对照 | 在原 .5 FxFloatView 上运行新增策略测试失败；恢复 .6 后通过。该对照证明输入防护回归有效，不证明渲染后端死锁已复现 |
| Scope/App/System | 最终 Demo 日志 00:52:27 / 31 / 35 分别完成 r1–r5，均 SUITE PASS；同尺寸 r3 有新的 layoutVersion |
| Home 首次创建及更新 | 00:51:43 由后台事件创建 System，r1–r5 全流程通过；00:51:50 桌面点击更新，r6 DRAW→280×144 LAYOUT→GEOMETRY→PRESENT；随后关闭成功 |
| 透明呈现/输入 | App HOLD PREPARED，截图无浮窗内容；点击浮窗覆盖位置，底层按钮计数从0到1，未关闭浮窗 |
| 原生输入补查 | 原生 uitest 点击 A/B 各一次，无父释放；从 A 起拖，位置变化且父释放一次、无补点击，下层 DOWN/MOVE/滚动均为0。注入流未记录子 CANCEL，不替代手指取消验收 |
| Hidden 对照 | 当前原生 RenderNode 仍收到 draw。这是机制差异的边界证据；本夹具没有复现业务后端在 Hidden 下停滞，不能宣称修复已在业务中验收 |
| 构建 | 独立 HAR、unsigned/signed Demo 构建通过。保留原兼容 API12、ANDROID_2 API20 运行门槛。DevEco 对预发布版本号及既有受版本保护 API 的警告仍存在 |

未做 CMP/消费应用构建与验收；没有把原生夹具通过提升为所有后端支持。无障碍读屏、键盘焦点、动画逐帧无闪烁、Pad/旋转/分屏/其他 API 版本仍需专项验收。原有取消与竞态有核心回归覆盖，不冒充本轮逐项真机验收。

## 接入次序

1. 换用 `floatingx-v0.1.1-yb.6.har`，模块依赖指向唯一来源，手动在消费工程同步依赖，确认解析版本与 `FLOATINGX_VERSION` 为 `0.1.1-yb.6`。
2. 继续使用原配置，保持原先明确选择的 ANDROID_2 / contentOwnsTap 等选项。此次修复不需要新增开关。
3. 预布局先设置 layoutOnly=true 并请求显示；确认宿主就绪，等待内容方本次 revision 的真实尺寸信号；调用 updateContentAndWaitForLayout，再 await move，最后 updateConfig(layoutOnly=false)。show/hide/updateConfig 等 Promise 仍需处理取消/失败。
4. 不把 SHOW 接到曝光统计；由接入方已有展示完成判断负责。保留本次内容 revision、实例和关闭状态检查，丢弃晚到尺寸回调。
5. 跨窗口内容在目标窗口 UIContext 初始化原生节点；新 HAR 不会修正内容引擎错误的窗口归属。
6. 消费方用实际内容验证首次显示、展开/收起、Home 更新。如果仍停滞，对照内容 draw、真实尺寸回调、原生布局、窗口几何四段定位，不能用非零占位尺寸直接放行展示。

这是 debug 预览 HAR。具体源码 commit、SHA256、SDK 元数据及源码条目核对结果见随包 manifest。公开交付不包含开发签名和原始设备日志。
