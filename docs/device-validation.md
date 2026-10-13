# 0.1.1-yb.1 验证记录

日期：2026-10-13。源码基于 `731e834245492c8b43256de861208ed2abfe1c0c`，本分支的对齐实现；发布包的精确源码 commit 与 SHA256 见随包 manifest。以下是组件验证，不包含接入应用的业务验收。

## 自动化与构建

- 核心测试（含 TypeScript 编译）：242/242 通过，无跳过。
- 独立 floatingx HAR 与 entry Demo HAP：DevEco/Hvigor 编译通过。
- 工具：DevEco Studio 26.0.0.461，Hvigor OHOS 插件 6.26.1。
- 包内元数据：compileSdkVersion `26.0.0.23`，compileSdkType `HarmonyOS`，buildMode `debug`；compatible/target API 12，apiReleaseType `Beta1`。这是开发验证包，不是生产 release 构建。
- HAR 无需应用签名；公开交付仅包含 HAR、未签名 Demo 和许可/校验文件。带本机开发签名的 Demo 仅本地使用。

## 真机冒烟

设备：SGT-AL10（DevEco 显示 HUAWEI Mate 80 Pro Max），HarmonyOS 7.0.0 / API 26。独立 Demo 使用已授权的 SYSTEM_FLOAT_WINDOW 开发签名，通过 DevEco Screen Mirroring 操作。

| 场景 | 实际观察 | 结论 |
| --- | --- | --- |
| 安装及启动 | 安装、EntryAbility 启动成功，等价验证首屏显示浮窗 | 通过 |
| Scope 更新布局 | 点击更新并等待布局，内容宽度从 160 变为 240，文字改变并返回布局结果 | 单次冒烟通过 |
| Scope 默认吸边 | 吸附开启、接管关闭，拖动释放后停靠右边缘并保留半隐藏片段 | 单次冒烟通过 |
| App 内容触控 | 应用浮窗出现，跨 Demo tab 仍可见；点击内部关闭按钮后消失 | 单次冒烟通过 |
| System 不降级创建 | 点击“显示系统浮窗（不降级）”，橙色系统窗口出现，页面显示 `actualScope=system` | 当前设备/开发签名通过 |
| System 更新布局 | 点击更新宽度，窗口可见宽度扩大，页面回读 `layout=4 width=280`，请求/实际位置均有值 | 单次冒烟通过 |
| System 拖动裁切 | 向左拖动后窗口只露出屏内片段，页面收到 UP 及累计位移 | 单次冒烟通过；未穷举比例 |
| System 前后台 | Home 后系统窗口仍显示，恢复 Demo 前台后仍可见；点击窗口内部关闭按钮后消失 | 单次冒烟通过 |
| 释放接管对照 | 镜像拖动部分被 Demo Tabs 横向分页手势接走，未取得足够稳定的开/关对照 | 待手指触控复核，不能标通过 |

测试中修复了 Demo 吸附开关文字不随配置刷新的问题，并重新编译、安装确认。组件无需为该 Demo 显示问题改变行为。

## 尚未验收

平板、API 12 真机、旋转/分屏、字号/密度变化、多指及系统取消、连续内容更新竞争、App 导航黑白名单完整路径、DisplayOnly 跨应用透传、System 权限拒绝及显式 fallback，均未在本轮真机逐项完成。

开发签名可创建 System 窗口不代表正式发布权限获批，也不代表其他系统版本/设备可用。核心测试中的原生替身覆盖不能代替上述设备验收；生产接入前按 [验证清单](fork-release-validation.md#最小验证路径) 补齐。
