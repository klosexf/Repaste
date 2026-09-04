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

/// 面板进出动效参数
/// 入场 ease-out（先快后缓、柔和落位）；退场 ease-in（加速离场），时长约为入场 3/4
private enum PanelMotion {
    /// 入场时长（notch 刘海垂落 / centered 自下方升起）
    static let arriveDuration: TimeInterval = 0.18
    /// 退场时长（离场快于入场）
    static let departDuration: TimeInterval = 0.14
    /// 收起动画中途重新展示的恢复时长
    static let recoverDuration: TimeInterval = 0.18
    /// 减弱动态效果（Reduce Motion）时的纯淡入 / 淡出时长
    static let fadeInDuration: TimeInterval = 0.18
    static let fadeOutDuration: TimeInterval = 0.14
    /// notch 模式滑入 / 滑出时与屏幕顶的间距（完全藏到刘海后方）
    static let notchGap: CGFloat = 10
    /// centered 模式入场升起 / 退场下沉的位移
    static let centeredOffset: CGFloat = 12
    /// 入场曲线：expo ease-out
    static let arriveTiming = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// 退场曲线：ease-in
    static let departTiming = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.84, 0)
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
/// 面板高度随内容自适应（最大约 560，且不超屏幕可用高度 - 120）
final class PanelController {
    /// 单例
    static let shared = PanelController()

    /// 面板状态机（视图与控制器共用）
    let viewModel = PanelViewModel()

    /// 承载 SwiftUI 内容的面板
    private let panel: RepastePanel

    /// SwiftUI 承载视图（用于计算内容自适应高度；死态自愈时整体重建，故为 var）
    private var hostingView: NSHostingView<PanelView>

    /// 当前展示模式（尺寸锚定计算用）
    private var currentMode: PanelMode = .notch

    /// 当前所在屏（多屏下面板在触发热区 / 胶囊的屏展示；内容高度重算时沿用）
    private weak var currentScreen: NSScreen?

    /// 面板展示代次（每次 show 递增；hide 完成回调校验代次，
    /// 防止渐隐期间被重新展示的面板被旧回调误 orderOut）
    private var showGeneration = 0

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
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

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

    /// 展示面板（入场过渡动画，不激活 App）
    /// notch 模式：面板从屏幕顶上方（刘海后方）滑落展开 + 淡入；
    /// centered 模式：自最终位置下方 12pt 升起 + 淡入；
    /// 系统开启「减弱动态效果」时退化为纯淡入（不位移）
    /// - Parameters:
    ///   - mode: 展示模式（刘海 / 居中）
    ///   - screen: 目标屏（nil = NSScreen.main；刘海热区 / 胶囊触发展开时传所在屏）
    ///   - trigger: 埋点触发来源（nil 时按 mode 推断：notch → "notch"、centered → "hotkey"）
    func show(mode: PanelMode, on screen: NSScreen? = nil, trigger: String? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        // 展示代次递增：使渐隐期间挂起的旧 hide 完成回调失效（防止刚展示的面板被误移出）
        showGeneration += 1
        currentMode = mode
        currentScreen = screen
        viewModel.isNotchMode = (mode == .notch)
        // notch 模式面板顶部延伸到屏幕外（notchTopOverhang），头部行需下移
        // 菜单栏 / 刘海高度 + 超出量，保证内容仍从菜单栏下沿开始
        viewModel.notchTopInset = (mode == .notch)
            ? (screen.frame.maxY - screen.visibleFrame.maxY) + Self.notchTopOverhang
            : 0

        // 恢复设置（tab / 来源筛选）、清空搜索、重置键盘选中、刷新数据快照
        viewModel.prepareForDisplay()
        EventLog.track(EventLog.panelOpen, ["trigger": trigger ?? (mode == .notch ? "notch" : "hotkey")])

        let finalFrame = computePanelFrame(screen: screen)

        // 收起动画尚未结束又重新展示：从当前位置 / 当前透明度平滑恢复到目标位，避免跳变
        if panel.isVisible && panel.alphaValue > 0.05 {
            // 先完整摘除再挂回（forceRemount）：canJoinAllSpaces+stationary 面板可能进入
            // 「可见但点击穿透」的失联态（WindowServer 仍合成绘制，事件命中区域却未挂载），
            // 单纯 orderFrontRegardless 只调层级、不重建事件挂载，必须 orderOut + orderFront
            // 强制重建；同 runloop 内无可见闪烁
            forceRemount()
            // 恢复路径同样重建 SwiftUI 树：手势图坏态若只靠「重新呼出」无法消除
            // （面板未真正收起时用户反复呼出都走本路径），死态会跨多次呼出存活——
            // 实测日志中出现过连续 3 次 panel_open 无效、第 4 次才恢复的序列
            rebuildContentView()
            let generation = showGeneration
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = PanelMotion.recoverDuration
                context.timingFunction = PanelMotion.arriveTiming
                panel.animator().alphaValue = 1
                panel.animator().setFrame(finalFrame, display: true)
            }, completionHandler: { [weak self] in
                // 恢复动画被后续动画打断时 alpha 的 model value 可能冻结在中途值，
                // 仍是当前代次时强制终态，避免半透明残影影响后续路径判断
                guard let self, generation == self.showGeneration, self.panel.isVisible else { return }
                self.panel.alphaValue = 1
            })
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // 入场起始 frame：notch 移到屏幕顶上方（完全藏于刘海后方）；centered 下移 12pt。
        // notch 的滑入起点在目标屏顶边上方，多屏纵向错位排列时该区域可能落在另一屏可见区，
        // 会在另一屏「闪一下」——此时退化为原地淡入（不位移）
        var startFrame = finalFrame
        if !reduceMotion {
            switch mode {
            case .notch:
                if !notchSlideOverlapsOtherScreen(screen: screen, panelHeight: finalFrame.height) {
                    startFrame.origin.y = screen.frame.maxY + PanelMotion.notchGap
                }
            case .centered:
                startFrame.origin.y -= PanelMotion.centeredOffset
            }
        }

        // 幽灵态防御：面板本应不可见却仍挂载（alpha 残留在低值的罕见态），先彻底移出保证干净入场
        if panel.isVisible { panel.orderOut(nil) }
        // 治愈性重置：整体重建 SwiftUI 树。hostingView 若全程常驻复用，「收起动画期间
        // 点击被打断」等序列会让 SwiftUI 手势图残留悬挂的按下/追踪态——之后所有点击
        // 进入窗口却不再触发任何按钮（跨面板重开永久存在，orderOut/orderFront 无法恢复）。
        // 视图 @State 均为轻量展示态（数据在 viewModel），重建无感且能清除一切累积坏态
        rebuildContentView()
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        // orderFrontRegardless 不激活 App；成为 key window（nonactivating 不激活 App）确保键盘事件到达
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? PanelMotion.fadeInDuration : PanelMotion.arriveDuration
            context.timingFunction = PanelMotion.arriveTiming
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(finalFrame, display: true)
            }
        }
    }

    /// 隐藏面板（退场过渡动画后移出）
    /// notch 模式：上滑缩回屏幕顶上方（刘海后方）+ 淡出；centered 模式：下沉 12pt + 淡出；
    /// 系统开启「减弱动态效果」时退化为纯淡出（不位移）
    func hide() {
        // 持久化来源筛选（rememberAppFilter 开启时保存 lastSourceFilter）
        viewModel.persistOnHide()
        let panel = self.panel
        guard panel.isVisible else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // 退场目标 frame：notch 上滑至屏幕顶上方（完全藏于刘海后方）；centered 下沉 12pt。
        // notch 的滑出终点在目标屏顶边上方，多屏纵向错位排列时会在另一屏「闪一下」，
        // 此时原地淡出（不位移）
        let endFrame: NSRect
        if reduceMotion {
            endFrame = panel.frame
        } else {
            switch currentMode {
            case .notch:
                if let screen = currentScreen ?? NSScreen.main ?? NSScreen.screens.first,
                   !notchSlideOverlapsOtherScreen(screen: screen, panelHeight: panel.frame.height) {
                    endFrame = CGRect(
                        x: panel.frame.minX,
                        y: screen.frame.maxY + PanelMotion.notchGap,
                        width: panel.frame.width,
                        height: panel.frame.height
                    )
                } else {
                    endFrame = panel.frame
                }
            case .centered:
                endFrame = panel.frame.offsetBy(dx: 0, dy: -PanelMotion.centeredOffset)
            }
        }

        // 记录当前代次：完成回调时校验，渐隐期间若发生重新展示（代次已变）则不移出
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? PanelMotion.fadeOutDuration : PanelMotion.departDuration
            context.timingFunction = PanelMotion.departTiming
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self, generation == self.showGeneration else { return }
            // 若动画期间面板被重新展示（alpha 回升），则不移出
            if self.panel.alphaValue < 0.05 {
                self.panel.orderOut(nil)
            } else if self.panel.isVisible {
                // 防御：渐隐动画被同名动画叠加后 alpha 的 model value 可能冻结在中间值
                // （多处并发触发两次 hide 时），无新展示代次时面板必须彻底移出——
                // 半透明残影挂在屏上会让后续 show() 误走「恢复路径」跳过事件挂载重建，
                // 形成可见但不可点击的死态
                self.panel.alphaValue = 0
                self.panel.orderOut(nil)
            }
        })
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
                y: screen.frame.maxY - size.height + Self.notchTopOverhang
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

    /// notch 滑入 / 滑出带是否落入其他屏幕可见区（多屏纵向错位排列时会在另一屏「闪一下」）。
    /// 滑出带 = 目标屏顶边上方、面板水平居中、高度覆盖「藏入刘海后方 notchGap + 面板高」的矩形；
    /// 任一其他屏 frame 与该带相交，说明面板顶边上方区域在那块屏上可见，滑动会被看见
    private func notchSlideOverlapsOtherScreen(screen: NSScreen, panelHeight: CGFloat) -> Bool {
        let band = CGRect(
            x: screen.frame.midX - DT.panelWidth / 2,
            y: screen.frame.maxY,
            width: DT.panelWidth,
            height: PanelMotion.notchGap + panelHeight
        )
        for other in NSScreen.screens where other !== screen {
            if other.frame.intersects(band) { return true }
        }
        return false
    }

    /// 按内容自适应高度重算并应用面板 frame
    /// - Parameter animated: 内容变化期间是否带动画过渡（notch 顶边锚定、centered 中心锚定）
    private func applyPanelFrame(screen: NSScreen, animated: Bool = false) {
        let newFrame = computePanelFrame(screen: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: false)
        }
    }

    // MARK: 内容视图重建

    /// 重建面板内容视图（SwiftUI 树全量重置；viewModel 为唯一数据源，跨重建保留）
    private func rebuildContentView() {
        let hosting = NSHostingView(rootView: PanelView(viewModel: viewModel))
        // 显式继承旧视图布局：赋 contentView 时 AppKit 通常会接管 frame，
        // 但窗口此刻的 content 布局可能与旧视图 frame 有偏差，显式设置兜底
        hosting.frame = hostingView.frame
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        hostingView = hosting
    }

    // MARK: 悬停收起支持（HotZoneWatcher / CapsuleController / HotKeyManager 使用）

    /// 面板当前是否可见（含渐隐动画期间，orderOut 前均为 true）
    var isPanelVisible: Bool { panel.isVisible }

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
        guard panel.isVisible, panel.alphaValue > 0.5 else { return }
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
