# 净卸 PureUninstaller

一款 macOS 原生应用卸载与残留清理工具，交互对标 Windows Geek Uninstaller：

**应用列表 → 选中卸载 → 扫描全部残留 → 树形预览、逐项勾选 → 二次确认 → 一键清理。**

只做卸载与残留清理，不做磁盘清理、内存加速、广告、推荐或常驻后台。

![净卸图标](Resources/AppIcon-1024.png)

---

## 系统要求

- Apple Silicon（M1/M2/M3/M4，arm64）
- macOS 14 Sonoma 或更高
- 默认不需要管理员权限；root-owned App 可选管理员移除，不需要关闭 SIP
- 卸载 App 本体和其他 App 的沙盒容器时，需要用户按需授予 macOS **完全磁盘访问权限**；这是系统隐私保护，可随时撤销
- 构建：Xcode 15+，或本机 Command Line Tools（已用 Swift 6.4 验证）

## 开箱即用

本机已经生成并安装好可直接运行的版本（`/Applications/净卸.app`）：

| 方式 | 操作 |
|---|---|
| **最快** | 打开 `/Applications/净卸.app`，或在启动台/聚焦搜索“净卸”；首次使用按界面提示授予完全磁盘访问权限 |
| **DMG** | 双击 `dist/净卸-1.0.0.dmg`，把“净卸”拖进 Applications |
| **直接运行** | 双击 `dist/净卸.app` |
| **命令行安装** | 在项目目录执行 `./Scripts/install.sh` |

> 首次打开如果被 Gatekeeper 拦截：右键 App → 打开。当前构建优先使用本机 Apple Development 证书签名，未做公证，只适合本机使用；如果要分发给别人，请参考下方“签名与公证”。

## 使用流程

1. 启动后自动扫描 `/Applications`、`~/Applications` 和系统应用目录。
2. 搜索或直接勾选一个/多个应用。
3. 首次使用如果出现黄色权限提示，点“打开设置”，在
   **系统设置 → 隐私与安全性 → 完全磁盘访问权限** 中勾选“净卸”，
   然后完全退出并重新打开净卸。授权一次即可；使用稳定签名后重新打包不会失效。
4. 选择模式并点击卸载：
   - **普通卸载**：优先发现并打开应用自带卸载器，然后结束关联进程、扫描残留。
   - **强制卸载**：跳过厂商卸载器，强制结束关联进程后深度清理，适用于应用损坏、无法退出或主程序已丢失。
5. 在树形预览中展开残留，取消勾选不想删的文件。
6. 默认“移到废纸篓”，可随时恢复；取消勾选后会切换为“永久删除”，并再次确认。
7. 完成后可导出纯文本卸载日志。

支持把 `.app` 直接拖进窗口，立即分析。

### 界面说明

- **已安装应用**：名称、版本、体积、来源（App Store / 开发者签名 / 本地签名 / macOS 系统）、安装位置、运行状态。净卸自身不会被列入可卸载应用。
- **系统保护应用**：来自 `/System` 的应用会置灰、锁定、不可选中，也不会扫描或删除其残留。
- **孤儿残留**：根据 Bundle ID、应用名和 LaunchAgent 启发式识别“主程序已删除但还有用户库残留”的候选，默认不勾选，必须人工确认。
- **关联进程**：查看某个应用的前台进程和后台 helper，支持单独结束、全部结束、强制结束。
- **权限引导**：顶栏盾牌和黄色提示条会显示完全磁盘访问状态；被 TCC 拒绝时，结果页直接给出打开设置入口，而不是只报一句“没有权限”。
- **可选管理员移除**：root-owned App（或父目录不可写的 App）会在列表/预览标记“需管理员”。确认后弹出 macOS 管理员密码，仅对选中的 `.app` 本体执行 `mv` 到废纸篓或 `rm`；不安装常驻 helper，不碰 `/System`。
- **日志**：记录时间、模式、应用信息、进程处理、逐项成功/失败、总释放空间；权限拒绝会单独标注。

## 安全边界（红线）

- 不修改 `/System`、不关闭 SIP、不修改系统快照。
- 系统自带应用只展示、置灰，不提供卸载入口，也不扫描其残留。
- 默认不请求管理员权限；root-owned App 提供**可选**的管理员移除，每次都会弹出系统密码，且只对选中的非系统 `.app` 生效。
- 不安装常驻特权 helper，不使用 `sudo` 命令，不修改 `/System` 或 SIP。
- 不主动申请全盘权限；完全磁盘访问权限由用户在“系统设置 → 隐私与安全性”中按需授权，可随时撤销。
- `/Library` 下的 LaunchDaemon、LaunchAgent、PrivilegedHelperTools 会展示，但**永远不会被本进程自动删除**，会标记为“需管理员权限”。
- 默认移入废纸篓；永久删除必须手动切换并二次确认。
- 关闭主窗口即完全退出，不常驻后台，不添加登录项。

## 残留扫描范围

用户库：

```
~/Library/Preferences          （含 ByHost）
~/Library/Caches
~/Library/Application Support
~/Library/Logs                 （含 DiagnosticReports / CrashReporter）
~/Library/LaunchAgents
~/Library/Containers
~/Library/Group Containers
~/Library/Application Scripts
~/Library/HTTPStorages
~/Library/WebKit
~/Library/Saved Application State
~/Library/Cookies
~/Library/Internet Plug-Ins
~/Library/Audio/Plug-Ins
~/Library/Frameworks
~/Library/QuickLook
~/Library/Spotlight
~/Library/Screen Savers
~/Library/PreferencePanes
~/Library/Services
~/Library/Input Methods
~/Library/Workflow
```

系统级（只读展示，需管理员权限，不会自动删除）：

```
/Library/Application Support
/Library/Caches
/Library/Preferences
/Library/Logs
/Library/LaunchAgents
/Library/LaunchDaemons
/Library/PrivilegedHelperTools
```

匹配依据：

- Bundle ID 精确匹配及 helper 前缀（`com.foo.App.helper`）
- 应用名 / 可执行文件名
- 团队 ID 前缀的 Group Container（`TEAMID.com.foo.App`）
- LaunchAgent / LaunchDaemon 的 `Label`、`Program`、`ProgramArguments` 中指向应用路径或 Bundle ID 的项
- 插件目录中的 bundle ID

## 孤儿残留识别

孤儿残留是启发式结果，不是绝对判断。规则：

- 只扫描用户库和少量 `/Library` 系统级位置；
- 排除 Apple 标识、已知系统组件和厂商后台服务；
- 排除已安装应用的 Bundle ID、helper、应用名和厂商容器；
- 根据“偏好设置 + 应用数据 / 容器 / LaunchAgent”等组合给出高/中/低置信度；
- 默认不勾选，低置信度默认隐藏；
- 清理前仍然进入同一套树形预览与二次确认。

做不到 100% 准确是该功能的固有限制，因此宁可漏报，也不默认删除。

## 构建

### 方式一：命令行（本机验证）

构建脚本会优先使用本机可用的 **Apple Development** 身份签名；没有时回退到 ad-hoc。
Apple Development / Developer ID 的 designated requirement 是稳定的，重新打包不会让
已经授予的完全磁盘访问权限失效；ad-hoc 每次打包 cdhash 都会变，会丢权限。

```bash
cd PureUninstaller
swift build -c release
./Scripts/build_app.sh      # 生成 dist/净卸.app
./Scripts/build_dmg.sh      # 生成 dist/净卸-1.0.0.dmg
./Scripts/install.sh        # 安装到 /Applications 并打开
```

本机只有 Command Line Tools，未包含 Xcode 的 `SwiftUIMacros` 插件，因此源码里用显式 `State` 存储声明代替 `@State` 宏（`_foo = State(...)` 加计算属性）。这是等价的属性包装写法，在 Xcode 中同样可编译；如果你用 Xcode 新建工程，也可以换回 `@State`。

### 方式二：Xcode

1. Xcode → File → New → Project → macOS → App。
2. Interface 选 SwiftUI，Language 选 Swift。
3. 删除模板生成的 `ContentView.swift` / `App.swift`，把 `Sources/PureUninstaller` 下的文件加入 target。
4. Target → General：
   - Minimum Deployments：macOS 14.0
   - Bundle Identifier：`com.pureuninstaller.app`
5. Target → Signing & Capabilities：**关闭 App Sandbox**（本工具需要读取用户库；不需要其他 entitlement）。
6. 使用 `Resources/Info.plist` 的键值，或至少配置：
   - `CFBundleDisplayName` / `CFBundleName` = 净卸
   - `CFBundleExecutable` = PureUninstaller
   - `CFBundleIconFile` = AppIcon
   - `LSMinimumSystemVersion` = 14.0
7. 运行后按 `Scripts/build_app.sh` 的方式生成独立 `.app`，或用 Product → Archive 导出。

也可以直接 `File → Open → Package.swift` 打开 SwiftPM 工程；但为了让 `.app` 带正确的 Info.plist 和图标，推荐用 `Scripts/build_app.sh` 组装。

### 打包 DMG

```bash
./Scripts/build_dmg.sh
```

脚本做的事情：

1. 编译 arm64 Release；
2. 组装 `dist/净卸.app`；
3. 创建包含 App 和 `Applications` 快捷方式的临时目录；
4. `hdiutil create -format UDZO` 生成压缩 DMG。

手动命令等价于：

```bash
mkdir -p build/dmg-stage
cp -R "dist/净卸.app" "build/dmg-stage/净卸.app"
ln -s /Applications "build/dmg-stage/Applications"
hdiutil create -volname "净卸" -srcfolder build/dmg-stage \
  -ov -format UDZO "dist/净卸-1.0.0.dmg"
```

### 签名与公证（对外分发）

当前构建优先使用本机 Apple Development 证书签名；它不是 Developer ID，也没有公证，只适合本机。管理员移除使用一次性 AppleScript 授权，不安装常驻 helper。
对外分发需要：

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "dist/净卸.app"

xcrun notarytool submit "dist/净卸-1.0.0.dmg" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple "dist/净卸-1.0.0.dmg"
```

## 项目结构

```
PureUninstaller/
├── Package.swift
├── Makefile
├── README.md
├── LICENSE
├── StarLogo.png                    # 用户提供的图标源文件（PNG）
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   ├── AppIcon-1024.png            # 去水印 + 圆角化后的图标
│   ├── IconSource.png              # 用户提供的原始图标（已转为 PNG）
│   ├── AppIcon.iconset/
│   └── ICON-NOTICE.md
├── Scripts/
│   ├── build_app.sh
│   ├── build_dmg.sh
│   └── install.sh
├── Sources/PureUninstaller/
│   ├── PureUninstallerApp.swift
│   ├── Models/                     # AppInfo / ResidueNode / 卸载结果
│   ├── Services/                   # 扫描、进程、删除、日志、安全校验
│   ├── Utilities/                  # 匹配规则、路径安全、大小格式化
│   ├── ViewModels/                 # AppModel / UninstallSession
│   └── Views/                      # SwiftUI 界面
└── dist/                           # 构建产物（.app / .dmg）
```

## 已知限制

- `/Library` 下的 root-owned 项目只展示不删除；需要用户用管理员权限手动处理。
- 卸载普通 App 的容器需要完全磁盘访问权限；未授权时系统会直接拒绝，不会出现可点击的“允许”弹窗。
- root-owned App 的移除需要管理员密码；这是 Unix 所有权限制，不是 TCC。
- root-owned App 的“移到废纸篓”或“永久删除”走可选的管理员授权路径；确认后会弹出系统密码，使用一次性 AppleScript 权限，不安装常驻 helper。
- 管理员移除只处理 `.app` 本体，不处理 `/Library` 系统级残留或任意用户路径。
- `LogiPluginService` 位于 `/Applications/Utilities`，父目录属于 root 且不可写；会走管理员移除。
- 部分沙盒容器受 `containermanagerd` 保护，删除可能失败；会记录在日志里。
- 极少数情况下 App 本体还需要“应用管理”权限；结果页提供打开入口。
- root-owned App 必须走可选管理员路径；普通用户和非管理员程序无法移动或删除它们。
- 孤儿残留是启发式判断，可能漏报或误报，默认不勾选。
- 厂商 `.sh` 卸载脚本不会自动执行，只在 Finder 中显示；`.app` 卸载器会打开让用户完成流程。
- 当前没有做 Developer ID 签名和公证；跨机器分发前请完成签名/公证。
- 不处理系统扩展、内核扩展、MDM 配置描述文件等需要管理员或系统策略的组件。

## 权限与 TCC 排查

macOS 把“移动其他 App 到废纸篓、访问其他 App 的容器”放在 TCC 隐私保护下。普通 App
没有完全磁盘访问权限时，即使 `/Applications` 目录本身可写，系统也会拒绝；错误文案可能非常
不直观（例如“没有访问该诊断报告的许可”）。这是系统行为，不是路径权限判断错误。

如果授权后仍然失败：

```bash
tccutil reset SystemPolicyAllFiles com.pureuninstaller.app
tccutil reset SystemPolicyAppDataDetailed com.pureuninstaller.app
tccutil reset SystemPolicyAppBundles com.pureuninstaller.app
```

然后完全退出净卸，重新打开，再到系统设置中重新添加 `/Applications/净卸.app`。
从 ad-hoc 构建切换到稳定签名后，必须重置一次 TCC 重新授权，因为旧条目绑定的是旧 cdhash。

## 快速自检

1. `swift build -c release` 无错误。
2. 打开 App，列表能看到用户应用和灰色系统应用。
3. 顶栏盾牌/黄色提示条显示完全磁盘访问状态；授权后提示条消失。
3. 搜索、勾选、批量选择正常。
4. 选中一个应用 → 预览出现应用本体 + 残留树。
5. 取消勾选一个残留，底部数量/体积随之变化。
6. 关闭预览取消，不产生任何删除。
7. 用一次性测试应用验证“移到废纸篓”后能从废纸篓恢复。
8. 导出日志，确认逐项路径与结果。
9. 未授权完全磁盘访问时，结果页应出现权限卡片和“打开完全磁盘访问权限”按钮。

## 图标

图标由用户提供（`StarLogo.png`），做过以下适配：

- 去除右下角“豆包 AI 生成”水印；
- 按原图轮廓生成透明圆角遮罩，去除白边；
- 生成 16–1024 的完整 `.iconset` 并编译为 `.icns`；
- 保留原始角色与配色，不改变画风。

详见 `Resources/ICON-NOTICE.md`。

## License

MIT。见 `LICENSE`。
