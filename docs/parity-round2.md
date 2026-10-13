# 0.1.1-yb.2：差异确认、实现与接入契约

本轮以 Android FloatingX 2.3.7 的 `a4b9dbfc1649accde832d2f70dd90d54bf5fac9a` 为行为依据，Harmony 从 `829dfb8a68f30ab0cdd441b9d8256dff62ea9b26` 继续。版本是组件接入预览版，不能解释为所有设备或嵌入式 UI 框架已通过验收。真实 CMP 示例按本轮范围暂缓；公开仓库没有业务代码、私有 UI bridge、私有 HAR 或应用状态规则。

## 差异与 Android 证据

下列链接固定到 Android commit，避免跟随上游变化。S 表示源码对照，T 表示核心回归，B 表示 ArkTS HAR/HAP 构建，D 表示本轮单台真机观察。

| 项目 | Android 代码与实际行为 | 本轮结果及限制 |
| --- | --- | --- |
| P01 子内容与父拖动 | [FxViewTouchHelper.interceptTouchEvent](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)：DOWN 不拦截，主指 MOVE 超阈值才拦截；ViewGroup 接管后取消子内容 | ANDROID_2 不再放置整窗 Block 覆盖层。子点击优先；轴向原生 Pan 仲裁成功后 cancelTouch 子原始事件并阻止待识别的竞争手势。S/T/B/D：手指从 A 起拖收到 CANCEL、父释放一次；B 单击一次。CMP、自定义 stopPropagation、已成功子长按/滚动仍待验证 |
| P02 阈值与长按 | 同上：ViewConfiguration.scaledTouchSlop；abs(dx)>=slop 或 abs(dy)>=slop；释放时 <150ms 点击、>=500ms 长按，中间区间不点击。配置 click listener 才启用点击/长按分类 | 显式 touchSlopVp，不能省略；需接入方提供 Android 实测 px/density 或经设备对照确认的值。Demo 的 8vp 只是测试输入。取消定时器冻结，按住后可继续拖动。S/T/B；精确边界与长按后拖动尚待设备对照 |
| P03 内容尺寸变化 | [FxViewLocationHelper.onSizeChanged](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewLocationHelper.kt) 重新夹紧；[FxSystemContainerView.onTouchMove](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxSystemContainerView.kt) 保持按下偏移与 raw 坐标 | ANDROID_2 内容测量不再无条件 cancel 主触点；仍更新尺寸与边界。宿主变化、隐藏/销毁/配置更新照常取消。S/T/B；连续手指拖动中 resize 待设备验收 |
| P04 安全区与原点 | [FxAppPlatformProvider.checkOrInitSafeArea](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/imp/app/FxAppPlatformProvider.kt)、[FxSystemContainerView.checkFullFlags](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxSystemContainerView.kt)：按实例选择避让/延伸 | HOST/AVOID_SYSTEM/EXTEND。App 用实际 Overlay 原点与主窗 avoid rect 求交；System 明确要求同显示、全屏主窗作为避让权威。不可证明的分屏/异屏数据报 CAPABILITY_UNSUPPORTED。S/T/B；动态系统区域、横屏/分屏、Phone/Pad 待设备验收 |
| P05 初始位置与 resize | [FxViewLocationHelper.getDefaultXY/checkOrRestoreLocation](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewLocationHelper.kt)：完整尺寸计算初始重力，再 safeX/Y；显式 XY 不叠 offset；resize 保留绝对坐标，吸附按旧侧 | W400/w100/r.5 的右初值从350修正为300；首个实测尺寸可重算初始重力，显式移动/触摸后不覆盖位置。resize 不再比例映射 Y，半隐藏非对称公式保留。S/T/B |
| P06 原生隐藏/销毁 | [FxBasicContainerView.onWindowVisibilityChanged](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt)、[FxBasisControlImp.isShow](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/imp/FxBasisControlImp.kt)：原生生命周期及实际显示查询 | 订阅 WINDOW_HIDDEN/DESTROYED；取消输入、旧异步结果与布局等待。isShow 加查 isWindowShowing。外部隐藏清除本次显示意图，需要显式 show；销毁终止实例，不自动重建。自身准备产生的 SHOWN 不触发恢复循环。S/T/B；真正 OS 外部关闭和竞争需设备验收 |
| P07 可触摸但不抢焦点 | [FxSystemContainerView.defaultFlags](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxSystemContainerView.kt)：默认 NOT_TOUCH_MODAL、NOT_FOCUSABLE | focusPolicy.NON_FOCUSABLE 显式 setWindowFocusable(false)，touchable 单独控制，prepare/show/hide/updateConfig 保持策略。DEFAULT 保留旧原生默认。S/T/B；键盘/底层焦点与窗外触控需真机组合验收 |
| V01 暂隐测量后定位 | [FxBasicContainerView.initView/onLayout](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt)：INVISIBLE 参与测量，布局定位后再显示 | layoutOnly 保留同一挂载节点，关闭可见及输入；公开 updateContentAndWaitForLayout → move → reveal。S/T/B/D：原生示例返回实际240宽并定位显示；这不是逐帧无闪烁或 CMP 验收 |
| V02 嵌入式 CMP | Android 原生 View/Compose 的分发不等于 Harmony 嵌入式渲染 | 按本轮明确范围暂缓。没有复制私有依赖；T 或 ArkUI D 不替代该项 |

ArkUI 使用 [onGestureRecognizerJudgeBegin 的 TouchRecognizer 参数和 cancelTouch](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-gesture-blocking-enhancement.md)（API20）。手指测试与 DevEco 镜像鼠标不同：后者在本机返回空 TouchRecognizer 列表，不能用鼠标路径证明子 CANCEL。两个轴向 Pan 保留 Android 的 OR 判定；全向 Pan 的欧氏距离不是等价替换。

## 最小配置与单位

```ts
const config = new FxConfig({
  boundaryMode: FxBoundaryMode.ANDROID_2,
  gestureMode: FxGestureMode.ANDROID_2,
  touchSlopVp: verifiedAndroidSlopPx / androidDensity,
  focusPolicy: FxFocusPolicy.NON_FOCUSABLE,
  safeAreaPolicy: FxSafeAreaPolicy.EXTEND,
  halfHide: true, halfHideRatio: 0.5, adsorb: false
});
```

`verifiedAndroidSlopPx/androidDensity` 是接入方采集值，不是组件硬编码。整窗手势要求运行 API20+；低版本明确失败，不静默使用旧覆盖层。LEGACY 和 CONTENT 是兼容旧用户的默认值，ANDROID_2 的 gestureMode 与 boundaryMode 分别显式启用；新手势不可同时配置旧 dragArea。

`onTouch` 观察主触点，`onRelease` 只决定父表面释放。子按钮点击成功时不会额外触发父 onRelease/onClick。没有业务命中坐标表，裁切采用真实内容偏移与原生命中。手势已成功的子内容、主动停止 raw 事件传播或自定义渲染器不能仅凭原生按钮试验声称兼容。

安全区含义：

- Scope：只支持 HOST，以实际局部宿主为边界；AVOID_SYSTEM/EXTEND 无主窗权威而报错。
- App HOST：Overlay 实测内容区域，不额外猜 inset。AVOID_SYSTEM：主窗口 avoid rectangles（window px）换算后与 Overlay 的 window-vp 原点求交，已避让处不重复扣除。EXTEND：仅接受已覆盖完整主窗的宿主，否则报错；组件不更改主窗全局沉浸式。
- System HOST/EXTEND：使用目标 display vp 区域，零 inset 表示选择延伸，不能称已完成系统避让。AVOID_SYSTEM：installSystem 额外传入 `viewportHost: loadedFxWindowHost`；同 display、全屏原点及尺寸匹配后读取主窗 system/cutout/navigation-indicator 区域。主窗分屏或不同 display 时不把小浮窗数据伪装成全屏数据。
- 公开位置/尺寸为 vp；System 的 density 是目标 display px/vp，App/Scope 的 pointer 是 window vp，System pointer 是 display vp。host-local 位置不可直接等同 window 触点位置；使用 delta 或几何快照。监听尺寸/avoid/display 变化后刷新边界。

## 暂隐测量与状态

可直接参考 `entry/src/main/ets/pages/ParityDemo.ets` 的 `prepare()`，不调用私有方法：

```ts
config.layoutOnly = true;
await control.updateConfig(config);
await control.show(); // 挂载保持布局的不可见内容
const geometry = await control.updateContentAndWaitForLayout(nextParams);
await control.move(geometry.viewport.size.width - geometry.content.width, targetY);
config.layoutOnly = false;
await control.updateConfig(config);
```

首次 App/Scope 宿主尚未 ready 时，show 的意图可保留；等有效挂载/布局通知后再运行更新，NO_HOST 不是可忽略的测量成功。生产接入须串行管理自己的更新，并处理隐藏、销毁、竞争更新的 Promise 失败，不用固定定时器补位。

- `layoutOnly=true`：内容挂载、可测量、视觉隐藏且不接收输入；getState 为 PREPARED，isShow=false。
- `layoutOnly=false` 且实际显示：isShow=true。layoutOnly 切换发 CONFIG；不把内部 SHOW 事件当屏幕合成帧完成。
- `hide()`：清除显示意图、取消等待；System 当前通过隐藏内容+关闭输入保留 OS 窗口。它不等于 OS hideWindow/destroyWindow。
- `cancel()`：终止并释放实例、内容、监听和窗口。
- 外部 WINDOW_HIDDEN：内部可见状态失效并发 HIDE，清除显示意图；只有后续显式 show 恢复。WINDOW_DESTROYED：终止实例和 tag。isShow 的原生查询可先于生命周期通知返回 false；getState 在事件前可能仍是上一状态，不是原生存在性查询。

## 覆盖矩阵

核心回归负责数学、实例、队列、原生边界替身；真机负责实际分发/绘制/焦点。以下保留每个场景，没有把待验证项写成通过。负责人：组件维护者负责通用实现/ArkUI；接入方负责实际内容框架和业务组合。

| ID | 场景 | 当前证据与剩余项 |
| --- | --- | --- |
| C01 | 创建、宿主迟到、权限拒绝 | T/B；单机开发签名 System 创建；拒绝路径尚待设备 |
| C02 | 原生按钮与空白点击 | T/B/D：按钮点击、从按钮起拖 CANCEL；空白原生 Tap 仍需对照 |
| C03 | CMP 点击/拖动 | 按本轮范围暂缓，接入方后续验证 |
| C04 | 长按后拖动、有/无处理 | S/T/B；手指长按后拖动待验证 |
| C05 | 等阈值、斜向阈值 | S/T/B；轴向两个 native Pan；设备阈值需接入方提供 |
| C06 | 多指、主指释放、Cancel | T/B；原生多指待验证 |
| C07 | 拖动中 resize、同尺寸更新 | T/B；手指持续拖动中改变实际尺寸待验证 |
| C08 | 释放接管后更新/移动/隐藏/销毁 | T/B；真机组合对照待验证 |
| C09 | 半隐藏、边界、完整贴边 | S/T/B；上一版本单机 System 裁切；本版组合待复核 |
| C10 | 初始重力、offset/margin、比例 | S/T/B，固定数值反例已回归 |
| C11 | 宽窄、首帧、同尺寸更新 | T/B/D：隐藏测量后240宽；逐帧闪烁及嵌入式内容未验收 |
| C12 | 裁切时子按钮点击/拖动 | B；通用原生命中路径已实现，边缘手指验收待补 |
| C13 | 页面过滤、宿主重建 | T/B；完整导航与 CMP 待补 |
| C14 | 前后台、App/System 载体切换 | T/B；业务切换策略仍由接入方负责 |
| C15 | OS 外部隐藏/销毁 | T/B；权威查询与事件均有接入，OS 实际外部关闭待补 |
| C16 | 双 System、同 tag 重建 | T/B；双窗口交替设备验证待补 |
| C17 | 旋转/分屏/resize/display | S/T/B；不支持权威避让时明确失败；设备待补 |
| C18 | 密度/字号、Phone/Pad | T/B；本轮只测一台 Phone，Pad 待补 |
| C19 | 安全区两策略/动态变化 | S/T/B；已避让不重复扣除、短侧切口分类有回归，设备待补 |
| C20 | 焦点/键盘/窗外/DisplayOnly | S/T/B；原生属性调用回归，键盘组合 D 待补 |
| C21 | show/hide/cancel 与迟到操作 | T/B；原生替身验证不等于实际 OS 竞争 |
| C22 | 更新竞争、旧布局、宿主失效 | T/B，布局版本和实例校验保留 |
| C23 | System 修正/拒绝/超时 | T/B，回读实际矩形，不默认为 App 降级 |
| C24 | 长时间更新/反复进入 | T/B 的释放回归；长时设备及 CMP 待补 |
| C25 | 旧 CONTENT/LEGACY 与 opt-in | T/B；原有测试继续通过；旧 API12 真机未新增验收 |

V02 以本轮明确范围为准。其余待验收项保留可执行清单，交付为有证据边界的预览包。实际构建、设备记录及包哈希见随包 manifest 与 [验证记录](device-validation.md)。
