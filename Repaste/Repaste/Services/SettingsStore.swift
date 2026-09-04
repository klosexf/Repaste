//
//  SettingsStore.swift
//  Repaste
//
//  全局设置中心：UserDefaults 后端 + @Observable 视图响应
//

import AppKit
import Foundation
import Observation
import Carbon.HIToolbox

// MARK: - 设置键定义

/// 全部设置键（UserDefaults 键名集中定义；recording_enabled 与 Task 1 已有键名对齐）
enum SettingsKey {
    /// 刘海悬停呼出开关
    static let hoverEnabled = "hover_enabled"
    /// 悬停灵敏度："sensitive" / "default" / "slow"
    static let hoverSensitivity = "hover_sensitivity"
    /// 前台 App 全屏时抑制刘海悬停呼出
    static let suppressFullscreen = "suppress_fullscreen"
    /// 历史上限条数（超出淘汰最旧未固定非模板条目）
    static let maxItems = "max_items"
    /// 图片保留天数（原图 TTL，超期删原图、保留缩略图）
    static let imageTtlDays = "image_ttl_days"
    /// 忽略录制的来源 App bundleId 列表
    static let ignoredBundleIds = "ignored_bundle_ids"
    /// 默认浏览器："system"（系统默认）/ 浏览器 bundleId
    static let defaultBrowser = "default_browser"
    /// 启动时读取当前剪贴板内容
    static let readClipboardOnLaunch = "read_clipboard_on_launch"
    /// 默认标签页："all" / "text" / "image" / "link"
    static let defaultTab = "default_tab"
    /// 来源应用筛选开关
    static let enableAppFilter = "enable_app_filter"
    /// 列表排序模式："recent_copied"（最近复制优先）/ "recent_used"（最近操作优先）
    static let sortMode = "sort_mode"
    /// 记住上次来源筛选开关
    static let rememberAppFilter = "remember_app_filter"
    /// 首次引导完成标记
    static let onboardingCompleted = "onboarding_completed"
    /// 粘贴目标："clipboard"（写回剪贴板）/ "app"（直接粘贴到目标 App）
    static let pasteTarget = "paste_target"
    /// 上次来源筛选（bundleId；nil = 未筛选）
    static let lastSourceFilter = "last_source_filter"
    /// 辅助功能权限已授予
    static let accessibilityGranted = "accessibility_granted"
    /// 录制开关（Task 1 已使用此键名，保持对齐）
    static let recordingEnabled = "recording_enabled"
    /// 呼出快捷键虚拟键码（默认 kVK_ANSI_V = 9）
    static let hotkeyKeyCode = "hotkey_key_code"
    /// 呼出快捷键 Carbon 修饰键掩码
    static let hotkeyModifiers = "hotkey_modifiers"
}

// MARK: - 悬停灵敏度档位

/// 悬停灵敏度档位与对应触发延迟
enum HoverSensitivity: String, CaseIterable {
    /// 灵敏：50ms
    case sensitive
    /// 默认：100ms
    case `default`
    /// 迟缓：250ms
    case slow

    /// 对应触发延迟（毫秒）
    var delayMillis: Int {
        switch self {
        case .sensitive: return 50
        case .default: return 100
        case .slow: return 250
        }
    }
}

// MARK: - 设置中心

/// 全局设置单例：属性读写 UserDefaults，@Observable 支持视图响应；
/// 监听 UserDefaults.didChangeNotification 同步外部写入（如视图层 @AppStorage）
@Observable
final class SettingsStore {
    /// 单例
    static let shared = SettingsStore()

    /// UserDefaults 后端
    private let defaults: UserDefaults

    /// didChangeNotification 观察令牌（必须持有，释放即注销）
    private var changeToken: (any NSObjectProtocol)?

    // MARK: 设置项

    /// 刘海悬停呼出（默认 true）
    var hoverEnabled: Bool = true {
        didSet {
            guard oldValue != hoverEnabled else { return }
            defaults.set(hoverEnabled, forKey: SettingsKey.hoverEnabled)
        }
    }

    /// 悬停灵敏度（默认 "default"）
    var hoverSensitivity: String = "default" {
        didSet {
            guard oldValue != hoverSensitivity else { return }
            defaults.set(hoverSensitivity, forKey: SettingsKey.hoverSensitivity)
        }
    }

    /// 悬停触发延迟（毫秒，由 hoverSensitivity 推导；无法识别的值按 default 处理）
    var hoverDelayMillis: Int {
        HoverSensitivity(rawValue: hoverSensitivity)?.delayMillis ?? HoverSensitivity.default.delayMillis
    }

    /// 前台 App 全屏时抑制刘海悬停呼出（默认 true；false = 全屏也可悬停呼出）
    var suppressFullscreen: Bool = true {
        didSet {
            guard oldValue != suppressFullscreen else { return }
            defaults.set(suppressFullscreen, forKey: SettingsKey.suppressFullscreen)
        }
    }

    /// 历史上限（默认 200）
    var maxItems: Int = 200 {
        didSet {
            guard oldValue != maxItems else { return }
            defaults.set(maxItems, forKey: SettingsKey.maxItems)
        }
    }

    /// 图片保留天数（默认 7）
    var imageTtlDays: Int = 7 {
        didSet {
            guard oldValue != imageTtlDays else { return }
            defaults.set(imageTtlDays, forKey: SettingsKey.imageTtlDays)
        }
    }

    /// 忽略录制的来源 App bundleId 列表（默认空）
    var ignoredBundleIds: [String] = [] {
        didSet {
            guard oldValue != ignoredBundleIds else { return }
            defaults.set(ignoredBundleIds, forKey: SettingsKey.ignoredBundleIds)
        }
    }

    /// 默认浏览器（默认 "system"；其余值为浏览器 bundleId）
    var defaultBrowser: String = "system" {
        didSet {
            guard oldValue != defaultBrowser else { return }
            defaults.set(defaultBrowser, forKey: SettingsKey.defaultBrowser)
        }
    }

    /// 启动时读取当前剪贴板（默认 false）
    var readClipboardOnLaunch: Bool = false {
        didSet {
            guard oldValue != readClipboardOnLaunch else { return }
            defaults.set(readClipboardOnLaunch, forKey: SettingsKey.readClipboardOnLaunch)
        }
    }

    /// 默认标签页（默认 "all"）
    var defaultTab: String = "all" {
        didSet {
            guard oldValue != defaultTab else { return }
            defaults.set(defaultTab, forKey: SettingsKey.defaultTab)
        }
    }

    /// 来源应用筛选开关（默认 true）
    var enableAppFilter: Bool = true {
        didSet {
            guard oldValue != enableAppFilter else { return }
            defaults.set(enableAppFilter, forKey: SettingsKey.enableAppFilter)
        }
    }

    /// 记住上次来源筛选（默认 true）
    var rememberAppFilter: Bool = true {
        didSet {
            guard oldValue != rememberAppFilter else { return }
            defaults.set(rememberAppFilter, forKey: SettingsKey.rememberAppFilter)
        }
    }

    /// 列表排序模式（默认 "recent_copied" 最近复制优先；"recent_used" = 最近操作优先，
    /// 复制与点击使用都会刷新排序位置）
    var sortMode: String = "recent_copied" {
        didSet {
            guard oldValue != sortMode else { return }
            defaults.set(sortMode, forKey: SettingsKey.sortMode)
        }
    }

    /// 首次引导完成标记（默认 false）
    var onboardingCompleted: Bool = false {
        didSet {
            guard oldValue != onboardingCompleted else { return }
            defaults.set(onboardingCompleted, forKey: SettingsKey.onboardingCompleted)
        }
    }

    /// 粘贴目标（默认 "clipboard"）
    var pasteTarget: String = "clipboard" {
        didSet {
            guard oldValue != pasteTarget else { return }
            defaults.set(pasteTarget, forKey: SettingsKey.pasteTarget)
        }
    }

    /// 上次来源筛选（默认 nil = 未筛选）
    var lastSourceFilter: String? = nil {
        didSet {
            guard oldValue != lastSourceFilter else { return }
            if let value = lastSourceFilter {
                defaults.set(value, forKey: SettingsKey.lastSourceFilter)
            } else {
                defaults.removeObject(forKey: SettingsKey.lastSourceFilter)
            }
        }
    }

    /// 辅助功能权限已授予（默认 false）
    var accessibilityGranted: Bool = false {
        didSet {
            guard oldValue != accessibilityGranted else { return }
            defaults.set(accessibilityGranted, forKey: SettingsKey.accessibilityGranted)
        }
    }

    /// 录制开关（默认 true；键名 recording_enabled 与 Task 1 对齐）
    var recordingEnabled: Bool = true {
        didSet {
            guard oldValue != recordingEnabled else { return }
            defaults.set(recordingEnabled, forKey: SettingsKey.recordingEnabled)
        }
    }

    /// 呼出快捷键虚拟键码（默认 kVK_ANSI_V = 9）
    var hotkeyKeyCode: Int = 9 {
        didSet {
            guard oldValue != hotkeyKeyCode else { return }
            defaults.set(hotkeyKeyCode, forKey: SettingsKey.hotkeyKeyCode)
        }
    }

    /// 呼出快捷键 Carbon 修饰键掩码（默认 optionKey | shiftKey）
    var hotkeyModifiers: UInt32 = UInt32(optionKey | shiftKey) {
        didSet {
            guard oldValue != hotkeyModifiers else { return }
            defaults.set(hotkeyModifiers, forKey: SettingsKey.hotkeyModifiers)
        }
    }

    /// 当前呼出快捷键展示文案（例如 ⌥⇧V）
    var hotkeyDisplay: String {
        HotKeyDisplay.string(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyModifiers)
    }

    // MARK: 初始化

    private init() {
        defaults = .standard

        // 注册全局默认值（未写入前的兜底读取值，同时惠及 @AppStorage 等直接读取方）
        defaults.register(defaults: [
            SettingsKey.hoverEnabled: true,
            SettingsKey.hoverSensitivity: "default",
            SettingsKey.suppressFullscreen: true,
            SettingsKey.maxItems: 200,
            SettingsKey.imageTtlDays: 7,
            SettingsKey.ignoredBundleIds: [String](),
            SettingsKey.defaultBrowser: "system",
            SettingsKey.readClipboardOnLaunch: false,
            SettingsKey.defaultTab: "all",
            SettingsKey.enableAppFilter: true,
            SettingsKey.rememberAppFilter: true,
            SettingsKey.onboardingCompleted: false,
            SettingsKey.pasteTarget: "clipboard",
            SettingsKey.accessibilityGranted: false,
            SettingsKey.recordingEnabled: true,
            SettingsKey.hotkeyKeyCode: 9,
            SettingsKey.hotkeyModifiers: UInt32(optionKey | shiftKey),
        ])

        // 从 UserDefaults 读取持久化值（属性默认值已完成存储初始化，可安全调用方法）
        reload()

        // 监听外部修改（如视图层 @AppStorage 直接写 UserDefaults），主线程刷新
        changeToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: 私有

    /// 从 UserDefaults 重新读取全部设置（值未变化的赋值不会写回，避免通知循环）
    private func reload() {
        hoverEnabled = defaults.bool(forKey: SettingsKey.hoverEnabled)
        hoverSensitivity = defaults.string(forKey: SettingsKey.hoverSensitivity) ?? "default"
        suppressFullscreen = defaults.bool(forKey: SettingsKey.suppressFullscreen)
        maxItems = defaults.integer(forKey: SettingsKey.maxItems)
        imageTtlDays = defaults.integer(forKey: SettingsKey.imageTtlDays)
        ignoredBundleIds = defaults.stringArray(forKey: SettingsKey.ignoredBundleIds) ?? []
        defaultBrowser = defaults.string(forKey: SettingsKey.defaultBrowser) ?? "system"
        readClipboardOnLaunch = defaults.bool(forKey: SettingsKey.readClipboardOnLaunch)
        defaultTab = defaults.string(forKey: SettingsKey.defaultTab) ?? "all"
        enableAppFilter = defaults.bool(forKey: SettingsKey.enableAppFilter)
        sortMode = defaults.string(forKey: SettingsKey.sortMode) ?? "recent_copied"
        rememberAppFilter = defaults.bool(forKey: SettingsKey.rememberAppFilter)
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted)
        pasteTarget = defaults.string(forKey: SettingsKey.pasteTarget) ?? "clipboard"
        lastSourceFilter = defaults.string(forKey: SettingsKey.lastSourceFilter)
        accessibilityGranted = defaults.bool(forKey: SettingsKey.accessibilityGranted)
        recordingEnabled = defaults.bool(forKey: SettingsKey.recordingEnabled)
        hotkeyKeyCode = defaults.integer(forKey: SettingsKey.hotkeyKeyCode)
        hotkeyModifiers = UInt32(defaults.integer(forKey: SettingsKey.hotkeyModifiers))
    }
}

// MARK: - 快捷键展示转换

/// 快捷键展示与 NSEvent / Carbon 掩码互转
enum HotKeyDisplay {
    /// 将 Carbon 修饰键掩码转为展示符号（⌘⌥⌃⇧）
    static func modifierString(carbonModifiers: UInt32) -> String {
        var result = ""
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        return result
    }

    /// 将 NSEvent.ModifierFlags 转换为 Carbon 修饰键掩码
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// 将虚拟键码与修饰键转为展示文案
    static func string(keyCode: Int, carbonModifiers: UInt32) -> String {
        modifierString(carbonModifiers: carbonModifiers) + keyString(for: keyCode)
    }

    /// 将虚拟键码转为展示键名
    static func keyString(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "⏎"
        case kVK_Escape: return "esc"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return String(keyCode)
        }
    }
}
