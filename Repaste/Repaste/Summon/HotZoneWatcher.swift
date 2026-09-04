//
//  HotZoneWatcher.swift
//  Repaste
//
//  刘海悬停状态机（呼出系统核心）：
//  [收起] --鼠标进入热区--> [待定] --停留 threshold--> [展开]
//  待定内离开热区回收起；展开后鼠标离开面板 leaveDelay 收起；收起后 cooldown 冷却。
//  抑制（任一命中热区直接失效）：任一鼠标键按下（拖拽）/ 前台 App 全屏（可关）/ 屏幕左右上角 120pt。
//

import AppKit
import CoreGraphics

// MARK: - 灵敏度档位扩展（离开延迟与冷却）

extension HoverSensitivity {
    /// 面板展开后鼠标离开面板的收起延迟（毫秒）：敏感 300 / 默认 400 / 迟缓 600
    var leaveDelayMillis: Int {
        switch self {
        case .sensitive: return 300
        case .default: return 400
        case .slow: return 600
        }
    }

    /// 面板收起后的冷却时长（毫秒，冷却内进入热区不触发）：敏感 300 / 默认 500 / 迟缓 800
    var cooldownMillis: Int {
        switch self {
        case .sensitive: return 300
        case .default: return 500
        case .slow: return 800
        }
    }
}

// MARK: - 刘海悬停状态机

/// 刘海悬停状态机（单例）：
/// - 热区：每个有刘海的屏一个（与刘海矩形严格一致，不外扩不下探）；无刘海屏走胶囊兜底（CapsuleController）
/// - 鼠标位置：global + local mouseMoved 事件驱动为主（globalMonitor 拿不到自己 App 的事件，local 配套覆盖面板自身），
///   待定复核与展开期收起检测由延时回调 / 60Hz 定时器读 NSEvent.mouseLocation（鼠标静止时兜底）
/// - 抑制检测：鼠标按下用 global/local monitor 按下与抬起配对计数（另用 pressedMouseButtons 兜底校正防卡死）；
///   全屏用 CGWindowList 找前台 App 的 layer 0 窗口与屏幕 frame 比对（0.5s 缓存防高频系统调用）
/// - hoverEnabled=false 时不装监听（设置变化动态装卸），关闭时记一次 hover_disabled
final class HotZoneWatcher: NSObject {
    /// 单例
    static let shared = HotZoneWatcher()

    // MARK: 状态机参数

    /// 屏幕左右上角抑制范围（pt；Apple 菜单与控制中心领地，永不触发）
    private static let cornerSuppressSpan: CGFloat = 120
    /// 「鼠标在面板上」判定容差（pt，面板 frame 四周外扩）
    private static let panelTolerance: CGFloat = 12
    /// 离开收起检测轮询间隔（60Hz）
    private static let pollInterval: TimeInterval = 1.0 / 60.0
    /// 光标位置兜底轮询间隔（30Hz）：mouseMoved 在快速移动时事件稀疏，可能整段跳过薄热区，
    /// 且光标带在热区内静止时不产生任何事件；此轮询兜底，保证「鼠标在刘海任意位置停留」都能可靠触发。
    private static let cursorPollInterval: TimeInterval = 1.0 / 30.0
    /// 全屏检测结果缓存时长（避免 mouseMoved 高频触发 CGWindowList 拷贝）
    private static let fullscreenCacheTTL: TimeInterval = 0.5

    /// 状态机状态
    private enum Phase {
        /// 收起（热区空闲）
        case collapsed
        /// 待定（鼠标在热区内，停留计时中）
        case pending
    }

    // MARK: 运行状态

    /// 当前状态
    private var phase: Phase = .collapsed
    /// 待定停留计时回调（进入热区安排，threshold 后复核）
    private var pendingWork: DispatchWorkItem?
    /// 冷却截止时刻（面板收起后 cooldownMillis 内热区不触发）
    private(set) var cooldownUntil: Date?
    /// 面板外连续停留起始时刻（nil = 在面板内 / 检测暂停中）
    private var outsideSince: Date?
    /// 离开收起检测定时器（面板悬停展开期间以 60Hz 运行）
    private var pollTimer: Timer?
    /// 光标位置兜底轮询定时器（hover 开启期间持续运行，30Hz）
    private var cursorPollTimer: Timer?

    /// 鼠标按下计数（global/local monitor 按下与抬起配对加减；> 0 = 拖拽中，抑制触发）
    private var pressedButtons = 0

    /// 各有刘海屏的热区（屏幕布局变化时重算）
    private var hotZones: [(screen: NSScreen, rect: CGRect)] = []
    /// 全屏检测缓存（时刻 + 屏幕帧 + 结果，短 TTL）
    private var fullscreenCacheDate = Date.distantPast
    private var fullscreenCacheFrame: CGRect = .zero
    private var fullscreenCacheValue = false

    /// 事件监听 token（必须持有，removeMonitor 用）
    private var globalMoveToken: Any?
    private var globalPressToken: Any?
    private var localMoveToken: Any?
    private var localPressToken: Any?
    /// 屏幕布局变化通知 token
    private var screenChangeToken: (any NSObjectProtocol)?
    /// App 退出通知 token
    private var terminateToken: (any NSObjectProtocol)?

    /// 设置中心
    private let settings = SettingsStore.shared

    private override init() {
        super.init()
    }

    // MARK: 生命周期

    /// 启动（幂等）：hoverEnabled=false 时不装监听；设置变化时动态装卸
    func start() {
        guard globalMoveToken == nil, screenChangeToken == nil else { return }
        rebuildHotZones()
        // 屏幕布局变化（插拔显示器 / 分辨率调整）→ 重算热区
        screenChangeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildHotZones()
        }
        // App 退出 → 移除 monitor / 定时器
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

    /// 停止：移除全部监听 / 定时器 / 通知
    func stop() {
        cancelPending()
        stopPollTimer()
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

    /// 观察 hoverEnabled：由开变关 → 移除监听 + 记一次 hover_disabled；由关变开 → 装监听
    /// （展开期收起定时器不受影响，让已展开的面板按规则自然收起）
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
                    self.cancelPending()
                    EventLog.track(EventLog.hoverDisabled)
                }
                // withObservationTracking 观察一次即失效，重新注册
                self.observeHoverEnabled()
            }
        }
    }

    /// 装事件监听（幂等）：global 拿不到自己 App 内的事件，local 配套覆盖面板自身
    private func installMonitors() {
        guard globalMoveToken == nil, localMoveToken == nil else { return }
        let moveMask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        let pressMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
        ]
        globalMoveToken = NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
            self?.handleMouseMoved()
        }
        globalPressToken = NSEvent.addGlobalMonitorForEvents(matching: pressMask) { [weak self] event in
            self?.handleButtonEvent(event)
        }
        localMoveToken = NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
        localPressToken = NSEvent.addLocalMonitorForEvents(matching: pressMask) { [weak self] event in
            self?.handleButtonEvent(event)
            return event
        }
        // 启动光标兜底轮询：补齐 mouseMoved 事件稀疏 / 静止时的漏检
        startCursorPoll()
    }

    /// 卸载事件监听
    private func removeMonitors() {
        if let token = globalMoveToken { NSEvent.removeMonitor(token); globalMoveToken = nil }
        if let token = globalPressToken { NSEvent.removeMonitor(token); globalPressToken = nil }
        if let token = localMoveToken { NSEvent.removeMonitor(token); localMoveToken = nil }
        if let token = localPressToken { NSEvent.removeMonitor(token); localPressToken = nil }
        stopCursorPoll()
    }

    // MARK: 事件处理

    /// 鼠标移动（含拖拽）事件驱动状态机
    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        switch phase {
        case .collapsed:
            evaluateEntry(at: location)
        case .pending:
            // threshold 内离开热区 → 立即回收起
            if hotZone(at: location) == nil {
                cancelPending()
            }
        }
    }

    /// 鼠标按下 / 抬起配对计数（拖拽期间抑制触发）
    private func handleButtonEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            pressedButtons += 1
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            pressedButtons = max(0, pressedButtons - 1)
        default:
            break
        }
    }

    /// 是否有任一鼠标键按下中（计数 + 系统状态双重判定；漏抬事件时由系统状态校正计数）
    private var isAnyButtonPressed: Bool {
        if NSEvent.pressedMouseButtons == 0 {
            pressedButtons = 0
        }
        return pressedButtons > 0 || NSEvent.pressedMouseButtons != 0
    }

    // MARK: 状态机流转

    /// 收起态判定进入待定：热区命中 + 面板未展开 + 无冷却 + 无抑制
    private func evaluateEntry(at location: NSPoint) {
        // 面板已展开（热区 / 快捷键 / 胶囊任一入口）不重复触发
        guard !PanelController.shared.isPanelVisible else { return }
        guard let zone = hotZone(at: location) else { return }
        // 收起后冷却期内不触发
        if let until = cooldownUntil, Date() < until { return }
        // 抑制：任一鼠标键按下中（拖拽文件经过刘海不触发）
        if isAnyButtonPressed { return }
        // 抑制：前台 App 全屏（默认开，suppressFullscreen 可关）
        if settings.suppressFullscreen, frontmostAppIsFullscreen(on: zone.screen) { return }
        // 抑制：左右上角 120pt（Apple 菜单与控制中心领地，永不触发）
        if isInSuppressedCorner(location, screen: zone.screen) { return }

        // 进入待定：threshold 后复核（鼠标可能静止，不依赖后续 mouseMoved）
        phase = .pending
        let threshold = Double(settings.hoverDelayMillis) / 1000.0
        let work = DispatchWorkItem { [weak self] in
            self?.confirmPending()
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + threshold, execute: work)
    }

    /// 待定到点复核：仍在热区且无抑制 → 展开面板（该屏、notch 位置）
    private func confirmPending() {
        guard phase == .pending else { return }
        pendingWork = nil
        let location = NSEvent.mouseLocation
        guard let zone = hotZone(at: location),
              !isAnyButtonPressed,
              !(settings.suppressFullscreen && frontmostAppIsFullscreen(on: zone.screen)),
              !isInSuppressedCorner(location, screen: zone.screen) else {
            phase = .collapsed
            return
        }
        phase = .collapsed
        PanelController.shared.show(mode: .notch, on: zone.screen)
        beginAutoHideTracking()
    }

    /// 取消待定（threshold 内离开热区 / 设置关闭 / 停止）
    private func cancelPending() {
        pendingWork?.cancel()
        pendingWork = nil
        phase = .collapsed
    }

    // MARK: 展开期收起检测（胶囊触发展开后同样复用）

    /// 面板展开后启动离开收起检测（刘海热区与胶囊触发展开后调用；快捷键居中面板不调用）
    func beginAutoHideTracking() {
        outsideSince = nil
        startPollTimer()
    }

    /// 冷却是否生效中（胶囊显示前询问，避免面板刚收起立即又被胶囊顶起）
    var cooldownActive: Bool {
        if let until = cooldownUntil { return Date() < until }
        return false
    }

    /// 启动 60Hz 检测定时器（target-selector，主线程 .common 模式）
    private func startPollTimer() {
        stopPollTimer()
        let timer = Timer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(pollTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// 停止检测定时器
    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        outsideSince = nil
    }

    // MARK: 光标位置兜底轮询

    /// 启动光标位置兜底轮询（30Hz）：见 cursorPollInterval 注释
    private func startCursorPoll() {
        stopCursorPoll()
        let timer = Timer(
            timeInterval: Self.cursorPollInterval,
            target: self,
            selector: #selector(cursorPollTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        cursorPollTimer = timer
    }

    /// 停止光标位置兜底轮询
    private func stopCursorPoll() {
        cursorPollTimer?.invalidate()
        cursorPollTimer = nil
    }

    /// 光标位置兜底轮询触发：与 mouseMoved 事件共用同一状态机（读 NSEvent.mouseLocation），
    /// 覆盖「快速移动事件稀疏跳过热区」与「光标带在热区内静止无事件」两类漏检。
    /// 面板展开期间由 evaluateEntry 的 isPanelVisible 守卫避免重复触发，无副作用。
    @objc private func cursorPollTick() {
        handleMouseMoved()
    }

    /// 60Hz 检测：面板可见且鼠标在面板 frame（+12pt 容差）外连续 leaveDelay → 收起并进入冷却
    @objc private func pollTick() {
        // 面板已被其他途径关闭（如面板内 Esc / 程序调用 hide）：停表并进入冷却兜底
        guard PanelController.shared.isPanelVisible else {
            stopPollTimer()
            enterCooldown()
            return
        }
        // 面板内浮层（⋮ 菜单 / 图片预览 / 弹窗 / 模板拖拽）打开时暂停检测，
        // 否则操作弹窗期间鼠标短暂离开面板会误收起
        if PanelController.shared.suspendAutoHide {
            outsideSince = nil
            return
        }
        let location = NSEvent.mouseLocation
        if PanelController.shared.panelHitFrame(tolerance: Self.panelTolerance).contains(location) {
            outsideSince = nil
            return
        }
        let now = Date()
        if outsideSince == nil {
            outsideSince = now
        }
        let leaveDelay = Double(leaveDelayMillis) / 1000.0
        if now.timeIntervalSince(outsideSince!) >= leaveDelay {
            stopPollTimer()
            PanelController.shared.hide()
            enterCooldown()
        }
    }

    /// 收起后进入冷却（时长按灵敏度档位）
    private func enterCooldown() {
        cooldownUntil = Date().addingTimeInterval(Double(cooldownMillis) / 1000.0)
    }

    /// 当前灵敏度档位对应的离开收起延迟（毫秒）
    private var leaveDelayMillis: Int {
        HoverSensitivity(rawValue: settings.hoverSensitivity)?.leaveDelayMillis
            ?? HoverSensitivity.default.leaveDelayMillis
    }

    /// 当前灵敏度档位对应的冷却时长（毫秒）
    private var cooldownMillis: Int {
        HoverSensitivity(rawValue: settings.hoverSensitivity)?.cooldownMillis
            ?? HoverSensitivity.default.cooldownMillis
    }

    // MARK: 热区计算

    /// 重算全部热区：每个有刘海的屏一个（无刘海屏走胶囊兜底，不建热区）
    private func rebuildHotZones() {
        hotZones = NSScreen.screens.compactMap { screen in
            guard let rect = notchHotZone(for: screen) else { return nil }
            return (screen, rect)
        }
    }

    /// 计算某屏的刘海热区：与刘海矩形严格一致（宽度 = 刘海宽，高度 = 刘海高，即
    /// safeAreaInsets.top，不外扩不下探）。鼠标不在刘海内就不触发。
    /// 刘海判定：safeAreaInsets.top > 0；刘海左右沿由 auxiliaryTopLeftArea.maxX 与
    /// auxiliaryTopRightArea.minX 推算。无刘海屏返回 nil。
    private func notchHotZone(for screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0 else { return nil }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }
        let left = normalizedToGlobal(leftArea, screen: screen)
        let right = normalizedToGlobal(rightArea, screen: screen)
        let notchMinX = left.maxX
        let notchMaxX = right.minX
        guard notchMaxX > notchMinX else { return nil }
        let notchHeight = screen.safeAreaInsets.top
        return CGRect(
            x: notchMinX,
            y: screen.frame.maxY - notchHeight,
            // 高度 +1：CGRect.contains 为半开区间 [min, max)，光标恰在屏幕最上沿（y==frame.maxY）
            // 时会被判为带外；+1 使上沿点含入，避免「贴顶不触发」。
            width: notchMaxX - notchMinX,
            height: notchHeight + 1
        )
    }

    /// auxiliaryTopLeft/RightArea 坐标基准归一：落在 screen.frame 范围内视为全局坐标直接用，
    /// 否则视为 screen-local 坐标（原点在该屏左下角），平移到全局基准
    private func normalizedToGlobal(_ rect: CGRect, screen: NSScreen) -> CGRect {
        if rect.minX >= screen.frame.minX - 1, rect.maxX <= screen.frame.maxX + 1 {
            return rect
        }
        return rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    /// 命中测试：返回 point 所在的热区（nil = 不在任何热区）
    private func hotZone(at point: NSPoint) -> (screen: NSScreen, rect: CGRect)? {
        for zone in hotZones where zone.rect.contains(point) {
            return zone
        }
        return nil
    }

    /// 屏幕左右上角 120pt 内（Apple 菜单与控制中心领地，永不触发）
    private func isInSuppressedCorner(_ point: NSPoint, screen: NSScreen) -> Bool {
        point.x - screen.frame.minX < Self.cornerSuppressSpan
            || screen.frame.maxX - point.x < Self.cornerSuppressSpan
    }

    // MARK: 全屏检测

    /// 前台 App 是否在该屏全屏（带 0.5s 缓存）
    private func frontmostAppIsFullscreen(on screen: NSScreen) -> Bool {
        let now = Date()
        if now.timeIntervalSince(fullscreenCacheDate) < Self.fullscreenCacheTTL,
           fullscreenCacheFrame == screen.frame {
            return fullscreenCacheValue
        }
        let result = computeFrontmostFullscreen(on: screen)
        fullscreenCacheDate = now
        fullscreenCacheFrame = screen.frame
        fullscreenCacheValue = result
        return result
    }

    /// 全屏检测：CGWindowList 找前台 App 的 layer 0 在屏窗口，
    /// frame 与该屏几乎相等（宽铺满 + 高度达到屏高 - 32，普通窗口最大只到
    /// visibleFrame、差约一个菜单栏高度 25-37px）即视为全屏
    private func computeFrontmostFullscreen(on screen: NSScreen) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        // 前台是本 App（如设置窗口激活）：不抑制
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        guard let cgScreen = cgFrame(of: screen) else { return false }
        let pid = frontApp.processIdentifier
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            if abs(frame.minX - cgScreen.minX) <= 2,
               abs(frame.width - cgScreen.width) <= 2,
               frame.minY >= cgScreen.minY - 2,
               frame.minY <= cgScreen.minY + 32,
               frame.height >= cgScreen.height - 32 {
                return true
            }
        }
        return false
    }

    /// NSScreen（AppKit 全局坐标，原点在主屏左下）→ CG 全局坐标（原点在主屏左上，
    /// CGWindowList 窗口 bounds 的基准）
    private func cgFrame(of screen: NSScreen) -> CGRect? {
        // 主屏 = frame 原点为 (0,0) 的屏（两套坐标系的换算基准）
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first else { return nil }
        return CGRect(
            x: screen.frame.minX,
            y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}
