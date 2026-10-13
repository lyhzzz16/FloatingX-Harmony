# Fork 版本交付、接入与验收

本 fork 的 `0.1.1-yb.1` 是 Android 2.3.7 对齐预览版。源码依据、能力边界和事件契约见 [对齐审计](android-parity.md)。MIT 允许维护 fork 和分发修改版本，分发时保留 LICENSE、上游版权及第三方许可信息。

## 先用本地 HAR 验证

不必先发布 OHPM。把固定版本 HAR 放到接入工程模块的 libs，保持公开 import 名 `floatingx`：

```json5
{
  "dependencies": {
    "floatingx": "file:./libs/floatingx-v0.1.1-yb.1.har"
  }
}
```

在 DevEco 执行依赖同步后，检查 lock 中解析出的版本和文件路径；应用里输出 `FLOATINGX_VERSION` 应为 `0.1.1-yb.1`。不要同时保留另一个来源的 floatingx。先保持默认 CONTENT 运行原有用例，再由接入方明确开启 ANDROID_2 及新回调。

HAR 自身无需应用签名；Demo HAP 在商业设备运行需要本机开发签名。签名材料、账号、设备标识及带证书的本地配置不进入仓库和公共 Release。系统浮窗的开发签名权限不代表正式上架权限已通过。

接入方在自己的开发分支替换依赖并手动构建实际应用，组件升级不会自动迁移应用的录音、导航和窗口切换逻辑。回滚时将依赖恢复为原 HAR 的固定文件名/校验值，重新同步并构建；新 API 调用也应随接入提交一起回退。

## 从源码构建

DevEco 中打开本仓库根目录。命令行将官方 Node、OHPM、Hvigor 加入 PATH，并按本机 DevEco 安装设置 DEVECO_SDK_HOME。首次安装依赖后按顺序运行：

```sh
npm install --ignore-scripts --no-audit --no-fund
npm run test:core
ohpm install --all
hvigorw --mode module -p module=floatingx@default -p product=default assembleHar --no-daemon
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

产物：

- `floatingx/build/default/outputs/default/floatingx.har`
- `entry/build/default/outputs/default/entry-default-unsigned.hap`
- 配置本机签名后另有 `entry-default-signed.hap`，仅供已授权设备本地验证。

本轮使用 DevEco Studio 26.0.0.461，自带 Hvigor OHOS 插件 6.26.1；工程 compatibleSdkVersion/targetSdkVersion 均为 5.0.0(12)，runtimeOS 为 HarmonyOS。编译 SDK 以包内元数据和随包 manifest 的实际值为准，不能因最低 API 12 就称使用 API 12 SDK 编译。未进行目录、依赖或缓存清理。

## 以后发布新版本

1. 在 fork 特性分支审阅变更，确认每项能力对应 Android 固定 commit；通过核心测试、HAR/HAP 编译及需要的设备验收。
2. 选择新预览版本，更新 floatingx 模块 manifest、Index.ets 的 FLOATINGX_VERSION、示例及 lock；固定源码 commit，再创建同名 `vX.Y.Z-suffix` tag。已分发版本不要复用。
3. 在 **lyhzzz16/FloatingX-Harmony** 创建 prerelease，描述变更、默认兼容方式、平台差异和未验证项。上游仓库的 Release 不会自动含有 fork 修改。
4. 上传该 commit 构建的 HAR、未签名 Demo、manifest、SHA256SUMS，并保留许可。manifest 应记录版本、源码 commit、构建 SDK/API、工具版本、签名状态和每个包的哈希。
5. 下载后用 `shasum -a 256 -c SHA256SUMS` 校验，再按本地 HAR 方式接入；无需变更 import 名。

仓库已有 `.github/workflows/release.yml`：发布 Release 才触发，不是推送特性分支即发布。它使用自己的固定 OpenHarmony 工具链并重新构建，不等同于本机 HarmonyOS 签名包；首次使用 fork Actions 前检查运行器架构、Actions 权限及产物结果。现有本地 CI 发布脚本会删除/重建其 staging 目录，本轮没有运行该脚本。不要为调试发布自动清理本地工程。

如果将来发布 OHPM 公共包，须使用你有权限的独立命名空间，不能抢占作者包名；统一处理消费者依赖键与 import。团队验证阶段使用版本化 HAR 更直接，也便于回滚。

## 最小验证路径

Demo 首页有「等价验证」「局部」「应用」「系统」「多实例」页。

| 场景 | 操作及预期 | 证据层级 |
| --- | --- | --- |
| 触摸配对 | 等价验证页按住不动、拖动、两指交替、触发系统取消；Up 只由真实事件产生，取消带原因 | 核心回归已覆盖；设备需复核 |
| 接管释放 | 打开接管释放和吸附后拖动，释放后不执行默认吸边；关闭接管后恢复默认；点按接管时不触发默认浮窗点击 | 核心回归已覆盖；设备需复核 |
| Android 边界 | 拖到左右边缘只显示对应片段，Y 不出上下有效范围；r=.25/.5 使用审计文档的原公式 | 数值回归已覆盖；设备需复核 |
| 更新及布局 | 各页点击更新并等待布局，160/240 或 220/280 等尺寸切换，显示实测尺寸、版本；快速连续更新不能返回旧结果 | 核心回归已覆盖；设备需复核 |
| 内容触控 | 应用/系统页仅标题为拖动区，内部按钮与底层按钮分别点击；隐藏后底层触控正常 | 组件回归+目标设备 |
| 页面/宿主变化 | App 黑名单页面、返回、Home/前台、旋转/分屏、字号/密度变化；实例及当前几何正确 | 组件回归+目标设备 |
| 多实例及竞争 | 多实例页按 tag 操作；反复 show/cancel、卸载重建；旧回调不能操作新实例 | 核心回归已覆盖；设备需复核 |
| System 限制 | 先选“不降级”创建；记录 actualScope 与错误码；再测试明确选择的 fallback，不能把 App 成功算 System 成功 | 原生替身回归+设备权限验证 |

记录每台设备型号、OS/API、源码 commit、HAR 哈希、Scope 类型、步骤、观察值/错误码和通过状态。手机与平板分别验收；一次成功不替代旋转/分屏/前后台场景。

本轮代码回归、编译和真机观察见 [验证记录](device-validation.md)。未完成的设备场景保留“未验证”，不得标成验收通过。
