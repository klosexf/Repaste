import Foundation
import CoreGraphics
import Testing
@testable import RepasteMotion

struct PanelTransitionTests {
    @Test(arguments: [60.0, 120.0])
    func completesAtBothRefreshRates(_ refreshRate: Double) {
        var motion = PanelTransition()
        motion.setExpanded(true)
        for _ in 0..<60 { motion.advance(by: 1 / refreshRate) }
        #expect(motion.isSettled)
        #expect(motion.progress == 1)
        motion.setExpanded(false)
        for _ in 0..<60 { motion.advance(by: 1 / refreshRate) }
        #expect(motion.isSettled)
        #expect(motion.progress == 0)
    }

    @Test func reversalKeepsPositionAndVelocityAndReachesNewTarget() {
        var motion = PanelTransition(isExpanded: true)
        motion.setExpanded(false)
        for _ in 0..<8 { motion.advance(by: 1 / 120) }
        let position = motion.progress
        let velocity = motion.velocity
        #expect(position > 0 && position < 1)
        #expect(velocity < 0)
        motion.setExpanded(true)
        #expect(motion.progress == position)
        #expect(motion.velocity == velocity)
        for _ in 0..<100 { motion.advance(by: 1 / 120) }
        #expect(motion.isSettled)
        #expect(motion.progress == 1)
    }

    @Test(arguments: [CGRect(x: -1200, y: 300, width: 500, height: 450),
                      CGRect(x: 450, y: -900, width: 500, height: 290)])
    func shellStaysAnchoredAndInsideFinalWindow(_ expanded: CGRect) {
        var motion = PanelTransition()
        let collapsed = CGSize(width: 190, height: 61)
        #expect(motion.notchFrame(expanded: expanded, collapsedSize: collapsed).size == collapsed)
        motion.setExpanded(true)
        for _ in 0..<120 {
            motion.advance(by: 1 / 120)
            let frame = motion.notchFrame(expanded: expanded, collapsedSize: collapsed)
            #expect(abs(frame.maxY - expanded.maxY) < 0.001)
            #expect(abs(frame.midX - expanded.midX) < 0.001)
            #expect(frame.width <= expanded.width && frame.height <= expanded.height)
            #expect(motion.contentOpacity >= 0 && motion.contentOpacity <= 1)
        }
        #expect(motion.notchFrame(expanded: expanded, collapsedSize: collapsed) == expanded)
    }

    @Test func repeatedReversalsAndDelayedFramesStillSettle() {
        var motion = PanelTransition()
        for i in 0..<30 {
            motion.setExpanded(i.isMultiple(of: 2))
            motion.advance(by: i.isMultiple(of: 3) ? 0.5 : 1 / 120)
            #expect(motion.progress.isFinite && motion.velocity.isFinite)
        }
        motion.setExpanded(false)
        for _ in 0..<120 { motion.advance(by: 1 / 120) }
        #expect(motion.isSettled)
        #expect(motion.progress == 0)
    }
}
