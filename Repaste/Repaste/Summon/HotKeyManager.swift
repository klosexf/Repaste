//
//  HotKeyManager.swift
//  Repaste
//
//  ⌥⇧V 全局快捷键（Carbon RegisterEventHotKey，零权限）：
//  任意前台 App 下呼出居中面板；面板已开时再按切换关闭。
//  注册失败（如组合被占用）记 EventLog 并静默（刘海入口不受影响）。
//

import AppKit
import Carbon.HIToolbox

// MARK: - 全局快捷键管理器

/// 全局快捷键管理器（单例）：⌥⇧V（keyCode 9 = V，optionKey|shiftKey）呼出 / 收起居中面板
final class HotKeyManager {
    /// 单例
    static let shared = HotKeyManager()

    /// 热键签名（四字符码 'RPST'，用于回调中校验事件归属）
    private static let signature: OSType = 0x5250_5354
    /// 热键 id（同一签名下区分多个热键；本产品仅一个）
    private static let hotKeyID: UInt32 = 1

    /// 热键注册引用
    private var hotKeyRef: EventHotKeyRef?
    /// 键盘事件处理器引用
    private var handlerRef: EventHandlerRef?
    /// App 退出通知 token
    private var terminateToken: (any NSObjectProtocol)?
    /// 设置变化通知 token（快捷键 keyCode / modifiers 变化后重启注册）
    private var settingsChangeToken: (any NSObjectProtocol)?

    private init() {
        // 监听 UserDefaults 变化：快捷键被修改后重新注册
        settingsChangeToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restart()
        }
    }

    // MARK: 生命周期

    /// 从 SettingsStore 读取当前快捷键并注册，安装事件处理器（幂等）
    func start() {
        guard hotKeyRef == nil else { return }

        let keyCode = UInt32(SettingsStore.shared.hotkeyKeyCode)
        let modifiers = SettingsStore.shared.hotkeyModifiers

        // 注册热键：合法自由组合，无系统冲突；被占用时静默失败，刘海入口仍可用
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            // 注册失败（如被其他 App 占用）：记日志静默，快捷键入口失效但刘海入口可用
            EventLog.track(EventLog.hotkeyRegisterFailed, ["status": String(status)])
            return
        }
        hotKeyRef = ref

        // 安装 kEventHotKeyPressed 处理器（C 函数指针回调，上下文经 Unmanaged 传 self）
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                // 校验热键 ID 归属（避免误处理同 target 上的其他热键）
                var hkID = EventHotKeyID()
                let got = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard got == noErr,
                      hkID.signature == HotKeyManager.signature,
                      hkID.id == HotKeyManager.hotKeyID else {
                    return noErr
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
                // Carbon 回调不保证主线程上下文：统一切主线程操作面板
                DispatchQueue.main.async {
                    manager.togglePanel()
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard installStatus == noErr, let handler else {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            EventLog.track(EventLog.hotkeyRegisterFailed, ["status": String(installStatus)])
            return
        }
        handlerRef = handler

        // App 退出 → 注销热键与处理器
        terminateToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    /// 注销快捷键与事件处理器（App 退出时）
    func stop() {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let terminateToken {
            NotificationCenter.default.removeObserver(terminateToken)
            self.terminateToken = nil
        }
    }

    /// 重新注册快捷键（设置变化后调用）
    func restart() {
        stop()
        start()
    }

    deinit {
        if let settingsChangeToken {
            NotificationCenter.default.removeObserver(settingsChangeToken)
        }
    }

    // MARK: 面板切换

    /// 面板已开 → 收起；未开 → 居中展开（埋点 trigger: hotkey，任意前台 App 均可呼出）
    private func togglePanel() {
        if PanelController.shared.isPanelExpanded {
            PanelController.shared.hide()
        } else if !PanelController.shared.reopenIfClosing() {
            PanelController.shared.show(mode: .centered, trigger: "hotkey")
        }
    }
}
