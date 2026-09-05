<p align="center">
  <img src="./assets/readme/hero.svg" width="100%"
       alt="Repaste · 刘海剪贴板：鼠标滑到刘海呼出剪贴板历史面板，面板展示来源 App、模板组标签页与链接跳转按钮">
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="#下载与安装"><img src="https://img.shields.io/badge/platform-macOS%2015%2B-8B6BFF" alt="platform: macOS 15+"></a>
  <a href="#方式二从源码构建开发者"><img src="https://img.shields.io/badge/Swift-5.0-8B6BFF" alt="Swift 5.0"></a>
  <a href="#技术架构"><img src="https://img.shields.io/badge/dependencies-zero-8B6BFF" alt="零第三方依赖"></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT-8B6BFF" alt="license: MIT"></a>
</p>

**Repaste（刘海剪贴板）** 是一款 macOS 原生剪贴板管理器。把鼠标滑到 MacBook 刘海停留 0.1 秒，剪贴板历史就从刘海向下展开；也可以随时按 `⌥⇧V` 从屏幕中央呼出。每条历史都标注**来自哪个 App、是什么类型**，常用内容可以沉淀为**模板组**，链接**一键直达浏览器**。所有数据只存在本机，**零系统权限**即可使用。

## 功能特性

- **双入口呼出**——刘海悬停 0.1 秒呼出下拉面板，`⌥⇧V` 屏幕居中呼出；两个入口共用同一列表，体验完全一致
- **来源 App 一眼可见**——每条历史显示来源应用（图标 + 名称），可按来源筛选，并能与搜索、类型标签叠加过滤
- **剪贴板历史**——文本 / 图片 / 链接 / 文件四类卡片，200 条上限自动淘汰（固定与模板条目除外），输入即搜
- **自定义模板组**——每个模板组是面板顶部一个标签页，可建任意多个；`⌘G` 把任意历史一键沉淀为模板，不参与淘汰
- **链接一键直开**——域名加粗突出（防钓鱼），点「跳转」直达浏览器；按住 `⌥` 可临时选择用哪个浏览器打开
- **⋮ 更多菜单**——按内容类型智能匹配：文本「无格式复制」、图片「查看大图」，以及通用的存入模板组 / 固定置顶 / 删除
- **防误触设计**——停留阈值 / 离开延迟 / 冷却期三段状态机；全屏应用默认抑制，屏幕左右上角（菜单与控制中心领地）永不抢触发
- **无刘海也能用**——非刘海 Mac 与外接显示器自动切换为顶部悬浮胶囊，鼠标靠近即浮现；多屏只在鼠标所在的屏幕展开


## 呼出方式

| 入口 | 操作 | 面板位置 |
| --- | --- | --- |
| 刘海悬停 | 鼠标滑入刘海热区，停留 100ms | 从刘海向下展开 |
| 全局快捷键 | `⌥⇧V`（默认，不与 Maccy / Raycast 冲突） | 屏幕居中 |
| 顶部胶囊 | 无刘海屏 / 外接屏，鼠标靠近顶边 | 胶囊展开同一面板 |

防误触状态机参数（均可在设置中调整灵敏度档位）：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| 停留阈值 | 100 ms | 敏感 50 / 默认 100 / 迟缓 250 三档 |
| 离开延迟 | 400 ms | 鼠标离开面板后收起，不拦截菜单栏点击 |
| 冷却期 | 800 ms | 收起后短时间内再进入不触发，防止上下抖动 |
| 抑制规则 | — | 鼠标按下中、全屏应用（可关闭）、屏幕左右上角 120pt 内永不触发 |

## 下载与安装

### 系统要求

- macOS 15.0 及以上
- 无需任何系统权限即可使用

### 方式一：下载 DMG（普通用户）

1. 下载 [`Repaste-V0.3.dmg`](https://github.com/klosexf/Repaste/releases/download/v0.3/Repaste-V0.3.dmg)（约 2 MB，从 GitHub Releases 下载）
2. 双击挂载 DMG，把 **Repaste** 拖到「应用程序」文件夹
3. 在「应用程序」中打开 Repaste

> 当前版本面向开发者分发，未做付费 Apple Developer 代码签名。首次启动时 macOS 可能提示「无法打开，因为来自身份不明的开发者」「无法验证开发者」或「无法检查是否包含恶意软件」，这是未签名应用的正常拦截，可按以下任一方式放行：
>
> 1. **系统设置放行**：系统设置 → 隐私与安全性 → 安全性，滚到底部点击「仍要打开」。
> 2. **右键打开**：在 Finder 的「应用程序」中找到 Repaste，右键 → 打开，在弹出的确认框中点击「打开」。
> 3. **终端移除隔离属性**：
>    ```bash
>    xattr -cr /Applications/Repaste.app
>    ```
>    执行后再次双击打开即可。

### 首次运行

首次启动会有简短引导：

| 步骤 | 内容 |
| --- | --- |
| 1. 欢迎来到刘海剪贴板 | 选择打开历史时默认显示的标签页 |
| 2. 隐私与本地存储 | 所有记录只存本机，密码类内容自动跳过 |
| 3. 试试看 | 把鼠标滑到屏幕顶部刘海，成功呼出即完成（也可跳过） |

引导全程**不索要任何系统权限**。默认模式下选中条目即写回剪贴板，回到任意应用按 `⌘V` 粘贴。

如果你在设置中开启「直接粘贴到正在使用的应用」（自动粘贴），才会单独提示需要辅助功能权限，按提示前往 **系统设置 → 隐私与安全性 → 辅助功能**，为 **Repaste** 打开开关即可；拒绝则自动回落为默认的仅复制模式。

### 方式二：从源码构建（开发者）

要求：Xcode 16+、macOS 15+ SDK。项目**零第三方依赖**，无需 Swift Package / CocoaPods 解析。

```bash
git clone https://github.com/klosexf/Repaste.git
cd Repaste
open Repaste/Repaste.xcodeproj   # 在 Xcode 中 ⌘R 直接运行
```

也可以用命令行构建：

```bash
xcodebuild -project Repaste/Repaste.xcodeproj -scheme Repaste build
```

## 快捷键

| 按键 | 动作 |
| --- | --- |
| `⌥⇧V` | 呼出 / 关闭面板 |
| `↑` `↓` | 选择条目 |
| `⏎` | 使用（写回剪贴板，面板收起） |
| `⌘⏎` | 打开链接 |
| `⌘G` | 存入模板组 |
| `⌫` | 删除条目 |
| `esc` | 关闭面板 |

## 隐私

- **纯本地存储**——不登录、不上传、不同步，历史与图片全部存在本机
- **密码自动跳过**——从 1Password / 钥匙串等应用复制的密码类内容（ConcealedType）完全不入库
- **零权限可用**——默认无需任何系统授权；仅「粘贴到正在使用的应用」这一可选项需要辅助功能授权
- **数据可控**——图片 7 天自动清理（TTL），可在设置中查看存储概览、清空历史或图片

## 技术架构

纯原生 macOS 开发，SwiftUI 构建 UI、AppKit 承载窗口（主面板为 borderless NSPanel，不抢前台焦点）。

| 层 | 技术 |
| --- | --- |
| UI 视图 | SwiftUI（面板、卡片、设置、引导） |
| 窗口层 | AppKit（NSPanel / NSWindow） |
| 数据层 | SwiftData（Clip / TemplateGroup，底层 SQLite）+ UserDefaults |
| 状态管理 | Observation（`@Observable`） |
| 全局热键 | Carbon RegisterEventHotKey（零权限） |
| 剪贴板监听 | NSPasteboard.changeCount 轮询（空闲 CPU ≈ 0） |
| 第三方依赖 | 无 |

```text
Repaste/
├── RepasteApp.swift            # 应用入口与窗口桥
├── DesignTokens.swift          # 设计系统（哑光纯黑 + 品牌紫）
├── Models/                     # SwiftData 模型：Clip、TemplateGroup
├── Services/                   # 剪贴板引擎
│   ├── ClipboardMonitor.swift  #   监听入库、类型判定、200 条淘汰、密码跳过
│   ├── ClipboardStore.swift    #   历史查询、筛选、固定、删除
│   ├── ImageStore.swift        #   图片落盘与 TTL 清理
│   ├── AutoPaster.swift        #   粘贴到前台应用（可选，需辅助功能授权）
│   └── SettingsStore.swift     #   设置项（改动即时生效）
├── Panel/                      # 主面板（刘海下拉 / 快捷键居中共用）
│   ├── PanelView.swift         #   搜索、标签页、来源条、卡片列表
│   └── ClipMoreMenu.swift      #   ⋮ 菜单（按类型组合）
├── Settings/                   # 设置窗口：常规 / 呼出 / 历史与隐私
├── Onboarding/                 # 首启引导（3 步，零权限）
└── Summon/                     # 呼出系统
    ├── HotZoneWatcher.swift    #   刘海热区状态机（防误触核心）
    ├── HotKeyManager.swift     #   ⌥⇧V 全局快捷键
    └── CapsuleController.swift #   无刘海屏 / 外接屏胶囊兜底
```

## 路线图

- [ ] iCloud / 多设备同步
- [ ] 模板变量与占位符（`{{日期}}`、`{{剪贴板}}`）
- [ ] 右键二级菜单与批量操作
- [ ] 链接预览卡片（标题与缩略图）
- [ ] 图片 OCR、拖拽出面板
- [ ] Sparkle 自动更新

## License

[MIT](LICENSE) © 2026 陈晓峰

---

<p align="center">把鼠标滑到刘海，试一试。</p>
