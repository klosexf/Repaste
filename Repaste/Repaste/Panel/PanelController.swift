//
//  PanelController.swift
//  Repaste
//
//  NSPanel 面板控制器：刘海剪贴板主面板的承载与展示控制
//

import AppKit
import SwiftUI

// MARK: - 面板展示模式

/// 面板展示模式
enum PanelMode {
    /// 刘海模式：屏幕顶部居中，顶边贴合屏幕顶
    case notch
    /// 居中模式：屏幕水平垂直居中
    case centered
}

// MARK: - 面板进出动效参数

/// 刘海连续形变；居中入口仍使用轻位移淡入。
private enum PanelMotion {
    static let frameInterval: TimeInterval = 1.0 / 120.0
    static let resizeDuration: TimeInterval = 0.15
    static let centeredOffset: CGFloat = 12
}

// MARK: - 面板窗口

/// 面板 NSPanel 子类：borderless 面板默认不能成为 key window，
/// 重写 canBecomeKey 使面板可接收键盘事件（nonactivating，不激活 App）
private final class RepastePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 窗口级事件入口：mouseDown 到达即记录投递日志（含浮层状态与命中测试结果）
    /// （与 item_used 构成「投递 → 动作」漏斗：死态时若投递日志仍在而动作缺失，
    /// 看 ovl 字段即知是哪个浮层在拦截；hit 字段直接给出命中视图类型，nil = 命中失败）
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let hit: String
            if let contentView {
                let point = contentView.convert(event.locationInWindow, from: nil)
                hit = contentView.hitTest(point).map { String(describing: Swift.type(of: $0)) } ?? "nil"
            } else {
                hit = "no-content"
            }
            EventLog.track(EventLog.panelMouseDelivered, [
                "alpha": String(format: "%.2f", alphaValue),
                "ovl": PanelController.shared.viewModel.overlayStateFlags,
                "hit": hit,
                // 几何探针：contentView 在窗口坐标系中的 frame（应为 0,0,W,H 铺满窗口）。
                // 若与窗口尺寸不符 = 承载视图布局错位（可见内容与命中区域分离）
                "cv": contentView.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.minY))" } ?? "none",
                "wh": String(Int(frame.height)),
            ])
        }
        super.sendEvent(event)
    }
}

// MARK: - 面板控制器

/// NSPanel 面板控制器（单例）
/// 展示 / 隐藏均不激活 App；面板展示时 makeKey（不激活 App）确保键盘事件到达；
/// 面板高度随内容自适应（最大约 450，且不超屏幕可用高度 - 120）
final class PanelController {
    /// 单例
    static let shared = PanelController()

    /// 面板状态机（视图与控制器共用）
    let viewModel = PanelViewModel()

    /// 承载 SwiftUI 内容的面板
    private let panel: RepastePanel

    /// SwiftUI 承载视图（用于计算内容自适应高度；死态自愈时整体重建，故为 var）
    private var hostingView: NSHostingView<PanelView>

    private let transitionView: PanelTransitionView
    private var transition = PanelTransition()
    private var motionTimer: Timer?
    private var lastMotionTime: TimeInterval = 0
    private var expandedFrame = CGRect.zero
    private var collapsedSize = CGSize(width: 96, height: 29)
    private var resizeFrom: CGRect?
    private var resizeTarget = CGRect.zero
    private var resizeElapsed: TimeInterval = 0
    private var pendingContentResize = false
    private var allowsHoverRecovery = false
    private var reduceMotion = false

    /// 当前展示模式（尺寸锚定计算用）
    private var currentMode: PanelMode = .notch

    /// 当前所在屏（多屏下面板在触发热区 / 胶囊的屏展示；内容高度重算时沿用）
    private weak var currentScreen: NSScreen?

    /// notch 模式面板顶部超出屏幕顶的距离（pt）：把窗口顶边与阴影抬到屏幕外，
    /// 既保留底部/两侧阴影的层次感，又避免顶边贴屏时窗口阴影合成出的细亮边
    private static let notchTopOverhang: CGFloat = 24

    /// Workspace 通知 token（Space 切换 / 显示器唤醒时重同步面板）
    private var workspaceTokens: [any NSObjectProtocol] = []
    /// NotificationCenter 通知 token（屏幕布局变化时重同步面板）
    private var appTokens: [any NSObjectProtocol] = []

    /// 点击穿透看门狗：全局 mouseDown 监听 token
    private var clickThroughToken: Any?
    /// 上次自愈时刻（节流：0.5s 内只重建一次，防连点重复重建）
    private var lastHealAt = Date.distantPast

    private init() {
        let panel = RepastePanel(
            contentRect: NSRect(x: 0, y: 0, width: DT.panelWidth, height: 290),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 阴影默认开启，保留面板底部/两侧的层次感；顶边白线隐患由 notchTopOverhang
        // 解决（面板顶部延伸到屏幕外）：窗口顶边与阴影被移到屏外，可见顶边是纯黑内容
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        let transitionView = PanelTransitionView(hosting: hostingView, contentWidth: DT.panelWidth, cornerRadius: DT.panelRadius)
        panel.contentView = transitionView

        self.panel = panel
        self.hostingView = hostingView
        self.transitionView = transitionView

        // 首次渲染即有数据（避免首次展示闪空态）
        viewModel.reload()
        // 观察内容规模变化，动态调整面板高度
        observeContentForSizing()
        // Space 切换 / 显示器唤醒后重同步面板
        observeWorkspaceForResync()
        // 点击穿透自愈看门狗（检测「可见但点击穿透」失联态并当场重建）
        installClickThroughWatchdog()
    }

    // MARK: 展示 / 隐藏

    /// 刘海外壳从实际刘海 / 胶囊展开；内容保持完整尺寸，系统减弱动态效果时只淡入。
    func show(mode: PanelMode, on screen: NSScreen? = nil, trigger: String? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        if panel.isVisible, currentMode == mode, currentScreen === screen,
           reopenIfClosing() { return }

        stopMotion()
        currentMode = mode
        currentScreen = screen
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        viewModel.isNotchMode = mode == .notch
        let overhang = topOverhang(on: screen)
        viewModel.notchTopInset = mode == .notch
            ? screen.frame.maxY - screen.visibleFrame.maxY + overhang : 0
        viewModel.prepareForDisplay()
        EventLog.track(EventLog.panelOpen, ["trigger": trigger ?? (mode == .notch ? "notch" : "hotkey")])

        // 每次完整重开仍重建 SwiftUI 树，保留既有点击失联自愈；反向恢复不重建。
        if panel.isVisible { panel.orderOut(nil) }
        rebuildContentView()
        expandedFrame = computePanelFrame(screen: screen)
        transitionView.contentSize = expandedFrame.size
        transitionView.isNotch = mode == .notch
        transitionView.isCapsule = mode == .notch && screen.safeAreaInsets.top == 0
        collapsedSize = collapsedPanelSize(on: screen, overhang: overhang)
        transition = PanelTransition()
        resizeFrom = nil
        pendingContentResize = false
        allowsHoverRecovery = false
        renderMotion()
        if mode == .notch { CapsuleController.shared.handOffToPanel() }
        panel.orderFrontRegardless()
        panel.makeKey()
        transition.setExpanded(true)
        startMotion()
    }

    /// 自动离开收起允许鼠标在动画结束前接回；Esc / 选用条目等主动关闭不被悬停反转。
    func hide(allowHoverRecovery: Bool = false) {
        guard panel.isVisible, transition.isExpanded else { return }
        allowsHoverRecovery = allowHoverRecovery
        resizeFrom = nil
        transition.setExpanded(false)
        startMotion()
    }

    /// 快捷键连续按下时从当前外形和速度反向，不重新开一块面板。
    @discardableResult
    func reopenIfClosing() -> Bool {
        guard panel.isVisible, !transition.isExpanded else { return false }
        allowsHoverRecovery = false
        transition.setExpanded(true)
        panel.makeKey()
        startMotion()
        if currentMode == .notch { HotZoneWatcher.shared.resumeAutoHideTracking() }
        return true
    }

    /// 只接回因鼠标离开而开始的关闭；命中实时外形，避免透明区域阻碍其他应用。
    func recoverHover(at point: CGPoint) -> Bool {
        guard allowsHoverRecovery, currentMode == .notch,
              NSEvent.pressedMouseButtons == 0,
              panelHitFrame(tolerance: 6).contains(point) else { return false }
        return reopenIfClosing()
    }

    private func startMotion() {
        guard motionTimer == nil else { return }
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: PanelMotion.frameInterval, repeats: true) { [weak self] _ in
            self?.advanceMotion()
        }
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func stopMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func advanceMotion() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - lastMotionTime, 0.064)
        lastMotionTime = now
        transition.advance(by: elapsed)
        if let from = resizeFrom {
            resizeElapsed += elapsed
            let t = min(1, resizeElapsed / PanelMotion.resizeDuration)
            let p = CGFloat(1 - pow(1 - t, 3))
            expandedFrame = CGRect(x: from.minX + (resizeTarget.minX - from.minX) * p,
                                   y: from.minY + (resizeTarget.minY - from.minY) * p,
                                   width: from.width + (resizeTarget.width - from.width) * p,
                                   height: from.height + (resizeTarget.height - from.height) * p)
            if t == 1 { resizeFrom = nil }
        }
        renderMotion()
        guard transition.isSettled, resizeFrom == nil else { return }
        stopMotion()
        if transition.isExpanded {
            if pendingContentResize, let screen = currentScreen {
                pendingContentResize = false
                applyPanelFrame(screen: screen, animated: true)
            }
        } else {
            panel.orderOut(nil)
            allowsHoverRecovery = false
            // 动画结束后才撤多选页脚 / 提交待删除内容，避免外壳收起中途跳高度。
            viewModel.persistOnHide()
            if currentMode == .notch, let screen = currentScreen {
                CapsuleController.shared.restoreAfterPanel(on: screen)
            }
        }
    }

    private func renderMotion() {
        let p = min(1, max(0, transition.progress))
        let frame: CGRect
        if reduceMotion {
            frame = expandedFrame
        } else if currentMode == .notch {
            frame = transition.notchFrame(expanded: expandedFrame, collapsedSize: collapsedSize)
        } else {
            frame = expandedFrame.offsetBy(dx: 0, dy: -PanelMotion.centeredOffset * (1 - p))
        }
        // 窗口只占当前可见外壳，透明区不会吞掉桌面点击；内部 SwiftUI 不跟着 resize。
        panel.setFrame(frame, display: false)
        transitionView.progress = reduceMotion ? 1 : p
        transitionView.updateGeometry()
        panel.alphaValue = reduceMotion || currentMode == .centered ? p : 1
        panel.invalidateShadow()
    }

    private func collapsedPanelSize(on screen: NSScreen, overhang: CGFloat) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = min(DT.panelWidth, max(96, right.minX - left.maxX))
            return CGSize(width: width, height: screen.safeAreaInsets.top + overhang)
        }
        return CGSize(width: 96, height: 5 + overhang)
    }

    /// 上方有另一屏时不把 24pt 黑色外壳画到相邻屏上。
    private func topOverhang(on screen: NSScreen) -> CGFloat {
        guard currentMode == .notch else { return 0 }
        let strip = CGRect(x: screen.frame.midX - DT.panelWidth / 2, y: screen.frame.maxY,
                           width: DT.panelWidth, height: Self.notchTopOverhang)
        return NSScreen.screens.contains { $0 !== screen && $0.frame.intersects(strip) }
            ? 0 : Self.notchTopOverhang
    }

    // MARK: 尺寸与位置

    /// 面板高度上限：内容自适应，最大约 450，且不超屏幕可用高度 - 120
    private func maxHeight(for screen: NSScreen) -> CGFloat {
        max(220, min(450, screen.visibleFrame.height - 120))
    }

    /// 计算面板目标 frame（宽度固定 500，高度内容自适应；notch 顶部居中贴合屏幕顶 / centered 屏幕居中）
    private func computePanelFrame(screen: NSScreen) -> NSRect {
        // fittingSize 由 SwiftUI 内容理想尺寸得出（宽度固定 500，列表区受 maxHeight 约束）
        let fitting = hostingView.fittingSize
        let height = min(max(fitting.height, 180), maxHeight(for: screen))
        let size = CGSize(width: DT.panelWidth, height: height)

        // 计算放置原点（AppKit 坐标系：原点在左下角）
        let origin: CGPoint
        switch currentMode {
        case .notch:
            // 顶部居中，面板顶部延伸到屏幕顶上方（notchTopOverhang）：
            // 窗口顶边与阴影在屏外不可见，可见顶边为纯黑内容，底部/两侧阴影保留层次感
            origin = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height + topOverhang(on: screen)
            )
        case .centered:
            // 屏幕水平垂直居中
            origin = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            )
        }

        return NSRect(origin: origin, size: size)
    }

    /// 内容尺寸变化与进出共用同一个驱动，避免两条动画同时争用窗口 frame。
    private func applyPanelFrame(screen: NSScreen, animated: Bool = false) {
        guard transition.isExpanded, transition.isSettled else {
            pendingContentResize = true
            return
        }
        let newFrame = computePanelFrame(screen: screen)
        guard newFrame != expandedFrame else { return }
        transitionView.contentSize = newFrame.size
        if animated && !reduceMotion {
            resizeFrom = expandedFrame
            resizeTarget = newFrame
            resizeElapsed = 0
            startMotion()
        } else {
            expandedFrame = newFrame
            renderMotion()
        }
    }

    // MARK: 内容视图重建

    /// 重建面板内容视图（SwiftUI 树全量重置；viewModel 为唯一数据源，跨重建保留）
    private func rebuildContentView() {
        let hosting = NSHostingView(rootView: PanelView(viewModel: viewModel))
        // 显式继承旧视图布局：赋 contentView 时 AppKit 通常会接管 frame，
        // 但窗口此刻的 content 布局可能与旧视图 frame 有偏差，显式设置兜底
        hosting.frame = hostingView.frame
        hostingView = hosting
        transitionView.replaceHosting(hosting)
    }

    // MARK: 悬停收起支持（HotZoneWatcher / CapsuleController / HotKeyManager 使用）

    /// 面板当前是否可见（含渐隐动画期间，orderOut 前均为 true）
    var isPanelVisible: Bool { panel.isVisible }

    /// 展开意图，与关闭动画尚可见的状态分开，供快捷键反向使用。
    var isPanelExpanded: Bool { panel.isVisible && transition.isExpanded }

    /// 面板命中区域（全局 AppKit 坐标，四周外扩 tolerance；悬停收起检测用）
    func panelHitFrame(tolerance: CGFloat) -> CGRect {
        panel.frame.insetBy(dx: -tolerance, dy: -tolerance)
    }

    /// 暂停自动收起：面板内浮层（⋮ 菜单 / 图片预览 / 弹窗 / 模板拖拽 / 浏览器选择）打开期间，
    /// 鼠标可能长时间离开面板 frame，不应触发「离开 400ms 收起」
    var suspendAutoHide: Bool {
        viewModel.moreMenuClip != nil
            || viewModel.templateMenuClip != nil
            || viewModel.previewingClip != nil
            || viewModel.activeDialog != nil
            || viewModel.draggingTemplateId != nil
            || viewModel.browserChooserClip != nil
    }

    // MARK: 内容尺寸观察

    /// 观察面板内容规模（列表条数 / 来源条与提示条显隐 / 模板组数量），
    /// 变化时动态调整面板高度（面板可见期间）
    private func observeContentForSizing() {
        withObservationTracking {
            _ = viewModel.contentSizeRevision
        } onChange: {
            // onChange 回调在非隔离上下文执行，捕获列表挂在 MainActor Task 上
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.panel.isVisible,
                   let screen = self.currentScreen ?? NSScreen.main ?? NSScreen.screens.first {
                    self.applyPanelFrame(screen: screen, animated: true)
                }
                // onChange 触发后观察即失效，重新注册
                self.observeContentForSizing()
            }
        }
    }

    // MARK: Workspace 重同步

    /// 观察 Workspace / App 通知：面板为 canJoinAllSpaces+stationary 的 borderless NSPanel，
    /// 在 Space 切换、显示器唤醒、屏幕布局变化后可能与 WindowServer 失联
    /// （面板仍显示但不参与事件命中测试——点击穿透、按钮全部无响应），此时需完整重建窗口挂载。
    /// 注意：App 前后台切换（didBecome/ResignActive）不做重同步——每次激活切换都
    /// orderOut+orderFront 反而增加挂载重建次数，失联由点击穿透看门狗兜底自愈
    private func observeWorkspaceForResync() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default

        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resyncPanelIfNeeded()
        })
        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resyncPanelIfNeeded()
        })
        // 显示器级别唤醒（比 didWake 更精确：仅屏幕唤醒，系统未睡眠）
        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resyncPanelIfNeeded()
        })
        // 屏幕布局变化（插拔显示器 / 分辨率调整）后窗口挂载可能失效
        appTokens.append(appCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resyncPanelIfNeeded()
        })
    }

    /// 面板可见时完整重建窗口挂载（不可见时不动作）。
    /// orderOut + orderFrontRegardless 强制 WindowServer 重新挂载事件命中区域——
    /// 单纯 orderFrontRegardless 只调整层级，无法修复「可见但点击穿透」的失联态
    private func resyncPanelIfNeeded() {
        guard panel.isVisible else { return }
        forceRemount()
    }

    /// 强制重建窗口挂载：orderOut + orderFrontRegardless 同一 runloop 内完成
    /// （无可见闪烁），迫使 WindowServer 重建事件命中区域
    private func forceRemount() {
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    // MARK: 点击穿透自愈看门狗

    /// 安装点击穿透看门狗。
    /// 原理：NSEvent 全局监听器只回调「投递给其他 App」的事件（本 App 收到的事件不会进
    /// 全局监听）。若面板可见（alpha > 0.5）且某次鼠标按下落在面板 frame 内（排除屏幕顶部
    /// 菜单栏/刘海带——该区域点击本就穿透给菜单栏），该事件本应命中我们的面板却进了别的
    /// App，说明面板处于「可见但点击穿透」的 WindowServer 失联态——立即强制重建挂载，
    /// 用户下一击即恢复。最坏只损失一次点击，而不是面板永久无响应。
    private func installClickThroughWatchdog() {
        guard clickThroughToken == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        clickThroughToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.healIfClickThrough(event)
        }
    }

    /// 判定点击是否穿透了可见面板，是则强制重建（节流 0.5s）
    private func healIfClickThrough(_ event: NSEvent) {
        let panel = self.panel
        guard panel.isVisible, transition.isExpanded, transition.isSettled,
              panel.alphaValue > 0.5 else { return }
        let location = NSEvent.mouseLocation
        guard panel.frame.contains(location) else { return }
        // 排除屏幕顶部菜单栏 / 刘海带（notch 模式面板 frame 覆盖该区域，但该区域
        // 无内容、点击本就穿透给菜单栏——面板健康时也如此，不能误判为失联）
        if let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            let menuBandHeight = screen.frame.maxY - screen.visibleFrame.maxY + 12
            if location.y > screen.frame.maxY - menuBandHeight { return }
        }
        // 节流：首个失联点击触发重建，后续连点已恢复、不再重复重建
        let now = Date()
        guard now.timeIntervalSince(lastHealAt) > 0.5 else { return }
        lastHealAt = now
        EventLog.track(EventLog.panelClickThroughHealed, [
            "alpha": String(format: "%.2f", panel.alphaValue),
        ])
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.forceRemount()
        }
    }
}
