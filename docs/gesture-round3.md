# 0.1.1-yb.4：手势差异评估与修复

## 结论与范围

此次审计确认 .3 将拦截阈值、父 MOVE、终止回调和窗口异步确认混在一起，存在真实 Android 行为差异。.4 修复可在独立组件内完成的内核与适配问题，保留默认 LEGACY；所有新行为显式选择 ANDROID_2。不加入应用状态、内容识别或私有依赖。

完整 Android ViewGroup 分发尚未实现。受控内容 dispatcher 是一种待验证的架构方案，并非 Android FloatingX 已有的同名 API；没有真实 childResult、disallow-intercept 与取消能力时，只新增协议不能消除差异。本轮不新增空壳 CONTROLLED 模式，不处理 CMP 取消或接入。原生 Pan 路径保留的局限明确列于下方，不能把它们标为不合理或已关闭。

## 固定源码依据

Android FloatingX 2.3.7，commit `a4b9dbfc1649accde832d2f70dd90d54bf5fac9a`：

- [FxViewTouchHelper](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/helper/FxViewTouchHelper.kt)：36–46 行父事件处理及最终观察；49–73 行拦截；75–102 行初始化/次指预检；105–114 行父 MOVE；117–145 行终止顺序、点击候选及处理时钟。
- [FxBasicContainerView](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxBasicContainerView.kt)：原生父事件入口、helper 调用与 View 处理结果。
- [FxSystemContainerView](https://github.com/Petterpx/FloatingX/blob/a4b9dbfc1649accde832d2f70dd90d54bf5fac9a/floatingx/src/main/java/com/petterp/floatingx/view/FxSystemContainerView.kt#L54-L78)：DOWN 保存 raw 偏移，MOVE 更新位置，原生坐标 toInt。
- [AOSP Android 16 ViewGroup](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/view/ViewGroup.java)：此次读取版本 dispatchTouchEvent 2812–2848 行，已有子目标时首次拦截 MOVE 用于取消子，不在该帧再次交父 onTouchEvent。它是平台分发证据，与 FloatingX helper 证据分开。

## 已修复

| 差异 | Android 行为 | .4 实现与证据 |
| --- | --- | --- |
| 拦截与父移动混用阈值 | 拦截使用轴向 >=；已交父的 MOVE 不再要求越阈值 | FxTouch.shouldIntercept 与 move 分开；零位移、小位移父 MOVE 仍处理。核心回归；真实直接父接收仍有下述归属限制 |
| 接管帧移动、重复坐标过滤 | 首次接管帧只取消子，后续物理 MOVE 才移父；相同坐标的新 MOVE 仍处理 | Pan start 只记归属，同时间戳 start/update 不重复移动；后续事件照常处理。核心覆盖首帧、重复回调和相同坐标；精确帧级原生时序尚未设备录制 |
| UP 补移动 | 终止不调用 MOVE | release.position 固定为最后父 MOVE，UP 原始坐标只进入快照。核心回归 |
| 一律忽略次指 UP | 父收到 POINTER_UP 就 touchCancel；子次指 UP 不产生父终止 | helper 状态与物理触点分别维护；后续真实父 UP 可再次终止；不自动提升次指为主指。核心及适配替身覆盖；真实多指 actionIndex 仍有限制 |
| 所有 CANCEL 不分类 | 父输入 CANCEL 走终止，符合候选时仍可 click/long；生命周期打断不是用户释放 | 区分子取消、父输入取消及 hide/destroy 等取消。核心回归 |
| packet 时间与候选恢复 | System.currentTimeMillis 计算时长；候选一旦越界不可恢复 | 注入处理时钟，149/150/499/500ms 覆盖；无 click listener 不触发库 long；真正回调 click 才消耗冷却。未模拟系统改时/任务调度对 Android postDelayed 的影响 |
| 观察 UP 冒充 helper onUp | helper onDown 独立；moveToEdge → onUp → click → onTouch | 新增 onDown/onUp；onRelease 保留为默认处理前的同步决策扩展，不把它改名冒充 Android onUp。核心顺序及重入回归 |
| 旧原生确认覆盖新 MOVE | Android 当前坐标随同步 MOVE 前进 | System 增加帧修订，旧确认仍更新已确认原生几何，但不回写较新的逻辑指针位置；回调新 move 优先，CONSUMED 不撤销已处理 MOVE。延迟确认/回调竞争替身回归 |
| DisplayOnly 禁用原生子内容 | 只跳过 helper，不统一禁用所有 View | ANDROID_2 保留子内容 enabled 和 System touchable；layoutOnly 仍隐藏且不可触摸。源码+替身；未做专门设备 DisplayOnly 验收 |
| 全局固定阈值 | 阈值来自容器 Context 的 ViewConfiguration | 使用所属 UIContext 的 PanGestureOptions.getDistance；显式正值优先。是平台参数映射，不承诺跨 OS 数值相同。见 [阈值文档](platform-touch-slop.md) |
| System px 四舍五入 | x/y.toInt 截断 | ANDROID_2 位置截断，LEGACY 保持 round，尺寸取整策略不变。数值核心回归 |

## 接口使用

```ts
new FxConfig({
  gestureMode: FxGestureMode.ANDROID_2,
  boundaryMode: FxBoundaryMode.ANDROID_2
  // touchSlopVp 可省略；由该浮窗的 UIContext 解析。
});
```

`onDown(snapshot)` 表示 helper 初始化，`onUp(snapshot)` 表示默认父终止通知；参数为副本、单位 vp、异步返回不阻塞。它们仅在 ANDROID_2 路径发出。`onTouch` 是观察，子序列 UP 不能用来替代父终止。

`onRelease(snapshot)` 仍需同步返回 DEFAULT/CONSUMED。CONSUMED 跳过默认吸附/回弹/存储/onUp/库点击，但不回滚已处理的拖动。要接管默认行为继续使用 onRelease；要对应 Android 默认 onUp 后置通知使用 onUp。库长按回调仍为 void/Promise，尚未实现 Android boolean 返回触发 haptic 的对应能力。

最低工程 API12 不变；ANDROID_2 原生子触摸取消要求运行 API20+，已有运行时能力检查。本次设备为 API26，并不构成 API20/23 或平板验收。默认阈值接口 API18，由该模式的 API20 门槛覆盖。

## 场景证据矩阵

T 表示真实组件算法/平台替身自动回归；D 表示独立 Demo 手指与日志；待验证/待实现不能用 T 代替。编号用于与手势审计用例互相定位，不表示总计 50 项均通过。

| 场景 | 本轮结论 |
| --- | --- |
| G01 子点击与父释放分离 | T；D 记录 A/B 单击及 A 起拖后的取消，无迟到 A click |
| G02 轴向对角线、G03 接管帧、G04 下一帧、G05 相同坐标 | T；D 只证明拖动/取消正常，未证明精确接管帧 |
| G06 父直接小 MOVE | 内核 T；真实空白区域父直接归属待实现，不能关闭 |
| G07 候选不可恢复 | T |
| G08 子长按后起拖、G09 disallow | 未验收；原生成功子手势/disallow 缺乏完整映射 |
| G10 子 CANCEL、G11 父 CANCEL、G12 生命周期 | T；未做系统输入 CANCEL 故障注入 |
| G13 次指不能引起主指误接管 | 选定指针前置校验 T；真实多指待验收 |
| G14 反向次指抵消 | 未解决：原生 Pan 自身可先受到多指仲裁限制，helper 校验不能让其提前触发 |
| G15 子次指 UP、G16 父次指 UP、G17 再次父 UP、G18 不自动换主指、G19 新次指预检 | T；原生触点顺序采用物理存活顺序映射，不是完整 MotionEvent actionIndex 证明 |
| G20 raw/Pan 重复事件 | DOWN 去重、Pan start/update 同时戳 T；无全局 packet 身份协议 |
| G21 时长边界、G22 listener 门槛、G23 冷却 | T；App/Scope 表面仍由 Tap 完成入口，真实父长按分发未关闭 |
| G24 UP 坐标、G25 延迟确认、G26 回调重入 | T；新 MOVE/取消/旧确认竞争覆盖，不宣称原生故障注入 |
| G27 拖动 resize、G28 旧布局/宿主回调 | 既有及本轮回归 T；本次无持续手指 resize 验收 |
| G29 ClickOnly、G30 DisplayOnly/layoutOnly | T/源码；原生 DisplayOnly 处理返回值未建立完整映射 |
| G31 多实例 | 既有回归 T；无双实例同时多指真机验收 |
| G32 宿主阈值 | T；D 示例省略阈值后单指拖动正常，未跨密度比较 |
| G33 半隐藏/空白目标归属 | 投影回归 T；System 不再额外合成 Tap，但任意空白/阴影真实目标归属未解决 |
| G34 宿主生命周期、LEGACY | T；D 证明 .4 System 前后台拖动及关闭，旋转/平板等仍待验收 |
| G35–G48 嵌入框架受控输入与取消 | 按本轮范围不实施、不验收；未引入 CMP 或其他私有依赖 |
| G49 观察与 helper 通知区分 | 新 onDown/onUp T；D 日志记录 helper 初始化/父终止；不表示新增原生 childResult 协议 |
| G50 新命令与旧确认竞争 | T；包括 CONSUMED 内新 move 保留，以及未发新命令时完成最后 MOVE |

## 不采纳的做法与保留缺口

不采用写死参考手机阈值、预先取消所有子内容、Pan distance=0、按钮矩形猜测真实 childResult、伪造 click/Cancel 或私有字段访问。这些不能由 Android 源码支撑，也会破坏组件通用性。

完整受控 dispatcher 的方向有依据，但必须先确认可提供真实命中结果、同步取消及 disallow 的通用宿主端口；本轮没有这样的可交付端口。现有原生 Pan 路由不能保证所有原生内容/已成功手势/stopPropagation/多指与 ViewGroup 完全相同。以上是剩余工程缺口，并非判定文档“不合理”而忽略。

## 验证与交付

280/280 核心回归通过，无跳过；最终 HAR 和独立 Demo HAP 构建通过。未构建接入应用，未运行清理。手指与窗口日志详情见 [设备记录](device-validation.md)。HAR 与源码提交逐文件校验、版本及 SHA256 见随包 manifest；带开发签名 Demo、账号信息和完整设备日志不公开分发。
