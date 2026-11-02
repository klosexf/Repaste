//
//  CapsuleController.swift
//  Repaste
//
//  胶囊兜底：无刘海屏 / 外接屏顶部中央的悬浮短条把手。
//  鼠标靠近顶部（该屏顶部 20pt 内、水平中央 1/3 区域）渐显 0.15s；
//  悬停胶囊 80ms 展开面板（该屏、notch 样式位置），收起规则同刘海状态机（离开 400ms + 冷却）。
//  多屏：只在鼠标当前所在屏出现；有刘海屏不显示胶囊（走刘海热区）。
//

import AppKit

// MARK: - 胶囊绘制视图

/// 胶囊绘制：白色 34% 透明度短条，仅底部两角圆角（顶边贴合屏幕顶边，呈小把手形态）
private final class CapsuleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // 圆角不超过高度（96×5 短条，底部圆角按规格 7，几何上夹到高度呈半圆收口）
        let radius = min(7, bounds.height)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.minX, y: bounds.minY + radius))
        path.appendArc(
            withCenter: NSPoint(x: bounds.minX + radius, y: bounds.minY + radius),
            radius: radius, startAngle: 180, endAngle: 270
        )
        path.line(to: NSPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.appendArc(
            withCenter: NSPoint(x: bounds.maxX - radius, y: bounds.minY + radius),
            radius: radius, startAngle: 270, endAngle: 0
        )
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        path.close()
        NSColor.white.withAlphaComponent(0.34).setFill()
        path.fill()
    }
}

// MARK: - 胶囊控制器

/// 胶囊兜底（单例）：无刘海屏的呼出把手。
/// - 事件驱动：global + local mouseMoved（global 拿不到自己 App 的事件，local 配套）
/// - hoverEnabled=false 时不装监听（与刘海热区同一总开关）
/// - 拖拽中（任一鼠标键按下）靠近顶部不显示，防误触
final class CapsuleController: NSObject {
    /// 单例
    static let shared = CapsuleController()

    // MARK: 参数

    /// 胶囊宽度（pt）
    private static let capsuleWidth: CGFloat = 96
    /// 胶囊高度（pt）
    private static let capsuleHeight: CGFloat = 5
    /// 鼠标靠近顶部判定深度（pt）
    private static let nearTopDepth: CGFloat = 20
    /// 悬停胶囊判定容差（pt，胶囊 frame 四周外扩）
    private static let hoverTolerance: CGFloat = 6
    /// 悬停展开延迟（80ms）
    private static let hoverDelay: TimeInterval = 0.08
    /// 渐显 / 渐隐时长（0.15s）
    private static let fadeDuration: TimeInterval = 0.15

    // MARK: 状态

    /// 胶囊面板（borderless 透明短条）
    private let panel: NSPanel
    /// 胶囊当前所在屏（渐隐完成后置 nil）
    private weak var currentScreen: NSScreen?
    /// 正在渐隐（渐隐期间不判定悬停展开）
    private var isFadingOut = false
    /// 悬停 80ms 展开计时回调
    private var hoverWork: DispatchWorkItem?

    /// 事件监听 token
    private var globalMoveToken: Any?
    private var localMoveToken: Any?
    /// 屏幕布局变化通知 token
    private var screenChangeToken: (any NSObjectProtocol)?
    /// App 退出通知 token
    private var terminateToken: (any NSObjectProtocol)?

    /// 设置中心
    private let settings = SettingsStore.shared

    private override init() {
        let size = NSSize(width: Self.capsuleWidth, height: Self.capsuleHeight)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // 鼠标事件穿透：胶囊位于菜单栏领地，不拦截点击；悬停判定用全局鼠标位置而非 hit test
        panel.ignoresMouseEvents = true
        panel.contentView = CapsuleView()
        self.panel = panel
        super.init()
    }

    // MARK: 生命周期

    /// 启动（幂等）：hoverEnabled=false 时不装监听
    func start() {
        guard globalMoveToken == nil, screenChangeToken == nil else { return }
        // 屏幕布局变化 → 立即隐藏（位置基准可能已变，下一次 mouseMoved 重新评估）
        screenChangeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
        // App 退出 → 移除监听 / 移出胶囊
        terminateToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        observeHoverEnabled()
        if settings.hoverEnabled {
            installMonitors()
        }
    }

    /// 停止：移除全部监听并移出胶囊
    func stop() {
        dismiss()
        removeMonitors()
        if let token = screenChangeToken {
            NotificationCenter.default.removeObserver(token)
            screenChangeToken = nil
        }
        if let token = terminateToken {
            NotificationCenter.default.removeObserver(token)
            terminateToken = nil
        }
    }

    // MARK: hoverEnabled 动态装卸

    /// 观察 hoverEnabled：由开变关 → 移除监听并隐藏胶囊；由关变开 → 装监听
    /// （胶囊与刘海热区共用悬停呼出总开关）
    private func observeHoverEnabled() {
        withObservationTracking {
            _ = settings.hoverEnabled
        } onChange: { [weak self] in
            // 先提升为 let 常量再进 Task，避免并发闭包引用 weak 捕获的 var self（Swift 6 报错）
            let observed = self
            Task { @MainActor in
                guard let self = observed else { return }
                if self.settings.hoverEnabled {
                    self.installMonitors()
                } else {
                    self.removeMonitors()
                    self.dismiss()
                }
                // withObservationTracking 观察一次即失效，重新注册
                self.observeHoverEnabled()
            }
        }
    }

    /// 装事件监听（幂等）
    private func installMonitors() {
        guard globalMoveToken == nil, localMoveToken == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        globalMoveToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.evaluate()
        }
        localMoveToken = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.evaluate()
            return event
        }
    }

    /// 卸载事件监听
    private func removeMonitors() {
        if let token = globalMoveToken { NSEvent.removeMonitor(token); globalMoveToken = nil }
        if let token = localMoveToken { NSEvent.removeMonitor(token); localMoveToken = nil }
    }

    // MARK: 状态评估（mouseMoved 驱动）

    /// 鼠标移动评估：决定胶囊显示 / 隐藏 / 悬停计时
    private func evaluate() {
        // 按住鼠标（拖拽）经过顶部不触发
        if NSEvent.pressedMouseButtons != 0 {
            dismiss()
            return
        }
        let location = NSEvent.mouseLocation
        guard let screen = screen(containing: location) else { return }

        // 有刘海屏走刘海热区（HotZoneWatcher），不显示胶囊
        if screen.safeAreaInsets.top > 0 {
            dismiss()
            return
        }
        if PanelController.shared.recoverHover(at: location) {
            HotZoneWatcher.shared.resumeAutoHideTracking()
            return
        }
        // 面板已展开（热区 / 快捷键 / 胶囊任一入口）：胶囊隐藏，避免与面板叠压
        if PanelController.shared.isPanelVisible {
            dismiss()
            return
        }
        // 面板收起冷却内不显示（刚收起防胶囊立即又顶起，冷却时长与刘海状态机同档位）
        if HotZoneWatcher.shared.cooldownActive {
            cancelHover()
            if isNearTop(location, screen: screen) {
                showCapsule(on: screen)
            } else {
                hideCapsule()
            }
            return
        }
        // 悬停胶囊上 → 80ms 计时展开
        if !isFadingOut, panel.isVisible, hoverFrame().contains(location) {
            beginHover()
            return
        }
        cancelHover()
        // 靠近该屏顶部（顶部 20pt 内 + 水平中央 1/3 区域，胶囊即位于其中）→ 渐显
        if isNearTop(location, screen: screen) {
            showCapsule(on: screen)
        } else {
            hideCapsule()
        }
    }

    /// 鼠标所在屏
    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// 鼠标靠近该屏顶部：顶部 20pt 内且水平在屏幕中央 1/3 区域
    /// （胶囊宽 96pt 位于正中，胶囊附近 ⊂ 中央 1/3，取并集即中央 1/3）
    private func isNearTop(_ point: NSPoint, screen: NSScreen) -> Bool {
        guard point.y >= screen.frame.maxY - Self.nearTopDepth else { return false }
        return abs(point.x - screen.frame.midX) <= screen.frame.width / 6
    }

    /// 悬停命中区域（胶囊 frame 四周外扩容差）
    private func hoverFrame() -> CGRect {
        panel.frame.insetBy(dx: -Self.hoverTolerance, dy: -Self.hoverTolerance)
    }

    /// 胶囊 frame：该屏顶部居中（96×5，顶边贴合屏幕顶边）
    private func capsuleFrame(on screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.midX - Self.capsuleWidth / 2,
            y: screen.frame.maxY - Self.capsuleHeight,
            width: Self.capsuleWidth,
            height: Self.capsuleHeight
        )
    }

    // MARK: 显示 / 隐藏

    /// 交接给同一位置的可变形外壳，不再让独立胶囊在面板上叠着淡出。
    func handOffToPanel() {
        cancelHover()
        panel.orderOut(nil)
        panel.alphaValue = 0
        isFadingOut = false
        currentScreen = nil
    }

    func restoreAfterPanel(on screen: NSScreen) {
        guard settings.hoverEnabled, screen.safeAreaInsets.top == 0,
              NSEvent.pressedMouseButtons == 0,
              isNearTop(NSEvent.mouseLocation, screen: screen) else { return }
        showCapsule(on: screen)
    }

    /// 渐显胶囊（0.15s），定位在该屏顶部居中
    private func showCapsule(on screen: NSScreen) {
        isFadingOut = false
        currentScreen = screen
        let frame = capsuleFrame(on: screen)
        if !panel.isVisible {
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        } else if panel.frame != frame {
            // 鼠标跨屏 / 布局变化：直接跳位
            panel.setFrame(frame, display: true)
        }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    /// 渐隐胶囊（0.15s 后移出）
    private func hideCapsule() {
        guard panel.isVisible, !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            // 渐隐期间又被显示（alpha 回升）则不移出
            if self.panel.alphaValue < 0.05 {
                self.panel.orderOut(nil)
                self.currentScreen = nil
            }
            self.isFadingOut = false
        })
    }

    /// 胶囊全退（取消悬停计时 + 渐隐）
    private func dismiss() {
        cancelHover()
        hideCapsule()
    }

    // MARK: 悬停展开

    /// 悬停 80ms 计时（在胶囊上保持 80ms 才展开）
    private func beginHover() {
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.expandPanel()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    /// 取消悬停计时
    private func cancelHover() {
        hoverWork?.cancel()
        hoverWork = nil
    }

    /// 展开面板（该屏、notch 样式位置；trigger 埋点 notch）；
    /// 收起规则复用刘海状态机（离开 400ms 收起 + 收起后冷却）
    private func expandPanel() {
        hoverWork = nil
        // 面板已被其他入口展开则只隐藏胶囊
        guard !PanelController.shared.isPanelVisible else {
            hideCapsule()
            return
        }
        guard let screen = currentScreen ?? screen(containing: NSEvent.mouseLocation) else { return }
        PanelController.shared.show(mode: .notch, on: screen)
        HotZoneWatcher.shared.beginAutoHideTracking()
    }
}
