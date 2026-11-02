import Foundation
import CoreGraphics

/// 可反向的同一条弹簧：改变目标时保留位置和速度，不重播入场动画。
struct PanelTransition {
    private(set) var progress: CGFloat
    private(set) var velocity: CGFloat = 0
    private(set) var target: CGFloat

    init(isExpanded: Bool = false) {
        progress = isExpanded ? 1 : 0
        target = progress
    }

    var isExpanded: Bool { target == 1 }
    var isSettled: Bool { progress == target && velocity == 0 }

    mutating func setExpanded(_ expanded: Bool) {
        target = expanded ? 1 : 0
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed > 0, !isSettled else { return }
        // 主线程短暂繁忙后只补最多 64ms，避免一步跨过终点；子步保证 60/120Hz 稳定。
        var remaining = min(elapsed, 0.064)
        let omega: CGFloat = isExpanded ? 8.2 / 0.32 : 8.2 / 0.25
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240.0)
            let dt = CGFloat(step)
            velocity += ((target - progress) * omega * omega - 2 * 0.91 * omega * velocity) * dt
            progress += velocity * dt
            remaining -= step
        }
        if abs(target - progress) < 0.001, abs(velocity) < 0.015 {
            progress = target
            velocity = 0
        }
    }

    /// 顶边和水平中心固定；宽度先舒展，高度随后跟上。只变窗口外壳，内容不缩放。
    func notchFrame(expanded: CGRect, collapsedSize: CGSize) -> CGRect {
        let p = min(1, max(0, progress))
        let horizontal = 1 - pow(1 - p, 2.25)
        let width = collapsedSize.width + (expanded.width - collapsedSize.width) * horizontal
        let height = collapsedSize.height + (expanded.height - collapsedSize.height) * p
        return CGRect(x: expanded.midX - width / 2, y: expanded.maxY - height,
                      width: width, height: height)
    }

    /// 外壳先出现，内容以正常尺寸进入；关闭时先收走文字，避免挤成一条线。
    var contentOpacity: CGFloat { min(1, max(0, (progress - 0.18) / 0.66)) }
}
