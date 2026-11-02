import AppKit
import SwiftUI
import Testing
@testable import RepasteMotion

@MainActor
struct PanelTransitionViewTests {
    @Test func swiftUIContentDoesNotForceTheWindowBackToFullWidth() {
        _ = NSApplication.shared
        let content = NSHostingView(rootView: Text("Repaste").frame(width: 500, height: 300))
        let view = PanelTransitionView(hosting: content, contentWidth: 500, cornerRadius: 28)
        view.contentSize = CGSize(width: 500, height: 300)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        for size in [CGSize(width: 190, height: 61), CGSize(width: 350, height: 200), view.contentSize] {
            window.setFrame(CGRect(origin: .zero, size: size), display: false)
            view.updateGeometry()
            window.layoutIfNeeded()
            #expect(window.frame.size == size)
            #expect(view.frame.size == size)
            #expect(content.frame.size == view.contentSize)
        }
    }

    @Test func contentKeepsFullSizeWhileShellChanges() {
        let content = NSView()
        let view = PanelTransitionView(hosting: content, contentWidth: 500, cornerRadius: 28)
        view.contentSize = CGSize(width: 500, height: 450)
        for (width, height, progress) in [(190.0, 61.0, 0.0), (430, 230, 0.5), (500, 450, 1)] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            view.progress = progress
            view.updateGeometry()
            #expect(content.frame.size == CGSize(width: 500, height: 450))
            #expect(content.frame.midX == view.bounds.midX)
            #expect(view.layer?.mask?.frame == view.bounds)
        }
        #expect(content.alphaValue == 1)
    }

    @Test func replacingContentRetainsMaskAndRestoresFullOpacity() {
        let view = PanelTransitionView(hosting: NSView(), contentWidth: 500, cornerRadius: 28)
        view.frame = CGRect(x: 0, y: 0, width: 250, height: 100)
        view.progress = 0
        view.updateGeometry()
        let replacement = NSView()
        view.replaceHosting(replacement)
        #expect(replacement.alphaValue == 0)
        view.frame = CGRect(x: 0, y: 0, width: 500, height: 290)
        view.progress = 1
        view.updateGeometry()
        #expect(replacement.alphaValue == 1)
        #expect(replacement.frame == view.bounds)
        #expect(view.layer?.mask?.frame == view.bounds)
    }

    @Test func nativeShellRendersWithOpaqueCenterAndClippedCorner() throws {
        let view = PanelTransitionView(hosting: NSView(), contentWidth: 500, cornerRadius: 28)
        view.frame = CGRect(x: 0, y: 0, width: 500, height: 300)
        view.contentSize = view.frame.size
        view.progress = 1
        view.updateGeometry()
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        #expect(center.alphaComponent > 0.95)
        // 顶部必须是贴屏平边，底部必须圆角，防止 flipped view 的遮罩上下颠倒。
        let topLeft = try #require(bitmap.colorAt(x: 0, y: 0))
        let bottomLeft = try #require(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1))
        #expect(topLeft.alphaComponent > 0.95)
        #expect(bottomLeft.alphaComponent < 0.1)
    }
}
