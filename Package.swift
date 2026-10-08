// swift-tools-version: 6.0
import PackageDescription

// Tests the selection and text composition without launching the clipboard monitor.
let package = Package(
    name: "RepasteCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "RepasteCore", targets: ["RepasteCore"])],
    targets: [
        .target(
            name: "RepasteCore",
            path: "Repaste/Repaste/Models",
            exclude: ["Clip.swift", "TemplateGroup.swift"],
            sources: ["MultiCopySelection.swift"]
        ),
        .testTarget(name: "RepasteCoreTests", dependencies: ["RepasteCore"]),
        .target(
            name: "RepastePasteboard",
            path: "Repaste/Repaste/Services",
            exclude: ["AutoPaster.swift", "ClipboardMonitor.swift", "ClipboardStore.swift", "EventLog.swift", "ImageStore.swift", "ModelContainerProvider.swift", "PasteboardReader.swift", "PasteboardWriter.swift", "SettingsStore.swift", "AppIconStore.swift"],
            sources: ["ImageBatchPasteboard.swift"]
        ),
        .testTarget(name: "RepastePasteboardTests", dependencies: ["RepastePasteboard"]),
    ]
)
