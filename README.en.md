<p align="center">
  <img src="./assets/readme/hero.en.svg" width="100%"
       alt="Repaste · Notch Clipboard: hover the notch to summon the clipboard history panel, showing source apps, template group tabs, and one-click link opening">
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="#download--installation"><img src="https://img.shields.io/badge/platform-macOS%2015%2B-8B6BFF" alt="platform: macOS 15+"></a>
  <a href="#option-2-build-from-source-developers"><img src="https://img.shields.io/badge/Swift-5.0-8B6BFF" alt="Swift 5.0"></a>
  <a href="#technical-architecture"><img src="https://img.shields.io/badge/dependencies-zero-8B6BFF" alt="zero third-party dependencies"></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT-8B6BFF" alt="license: MIT"></a>
</p>

**Repaste (Notch Clipboard)** is a native macOS clipboard manager. Hover your mouse over the MacBook notch for 0.1 seconds and your clipboard history unfolds right below it; or press `⌥⇧V` anytime to summon it at the center of the screen. Every entry is labeled with **which app it came from and what type it is**, frequently used items can be saved as **template groups**, and links **open in the browser with one click**. All data stays on your Mac — **zero system permissions** required.

## Features

- **Two summon entrances** — hover the notch for 0.1s to open the dropdown panel, or press `⌥⇧V` to summon it centered on screen; both entrances share the same list for a consistent experience
- **Source app at a glance** — every entry shows its source app (icon + name); filter by source, combinable with search and type tabs
- **Clipboard history** — text / image / link / file cards with a 200-entry rolling cap (pinned and template items excluded); search as you type
- **Custom template groups** — each group is a tab at the top of the panel; create as many as you like; `⌘G` turns any history entry into a template, exempt from eviction
- **One-click link opening** — domain highlighted in bold (anti-phishing); click "Open" to jump straight to the browser; hold `⌥` to temporarily choose which browser to use
- **⋮ More menu** — actions matched to content type: "Copy without formatting" for text, "View large" for images, plus save-to-template / pin / delete
- **False-trigger protection** — a three-stage state machine (dwell threshold / leave delay / cooldown); suppressed in full-screen apps by default; never triggers in the top screen corners (menu bar & Control Center territory)
- **Works without a notch** — non-notch Macs and external displays automatically fall back to a floating top capsule that appears when the mouse approaches; on multi-screen setups the panel only opens on the screen the mouse is on

## Summoning the Panel

| Entrance | Action | Panel position |
| --- | --- | --- |
| Notch hover | Slide the mouse into the notch hot zone, dwell 100ms | Unfolds downward from the notch |
| Global hotkey | `⌥⇧V` (default, no conflict with Maccy / Raycast) | Centered on screen |
| Top capsule | On non-notch / external screens, move the mouse near the top edge | Capsule expands into the same panel |

Anti-false-trigger state machine parameters (sensitivity adjustable in Settings):

| Parameter | Default | Notes |
| --- | --- | --- |
| Dwell threshold | 100 ms | Three levels: Sensitive 50 / Default 100 / Relaxed 250 |
| Leave delay | 400 ms | Panel collapses after the mouse leaves; never blocks menu-bar clicks |
| Cooldown | 800 ms | Re-entering shortly after closing won't trigger, preventing flicker |
| Suppression | - | Never triggers while a mouse button is held, in full-screen apps (can be disabled), or within 120pt of the top screen corners |

## Download & Installation

### System Requirements

- macOS 15.0 or later
- No system permissions required

### Option 1: Download the DMG (regular users)

1. Download [`Repaste-V0.3.dmg`](https://github.com/klosexf/Repaste/releases/download/v0.3/Repaste-V0.3.dmg) (~2 MB, from GitHub Releases)
2. Double-click to mount the DMG, then drag **Repaste** into the Applications folder
3. Open Repaste from Applications

> This build is distributed for developers and is not signed with a paid Apple Developer certificate. On first launch, macOS may show "cannot be opened because it is from an unidentified developer", "cannot verify the developer", or "cannot check it for malicious software". This is the normal Gatekeeper block for unsigned apps; allow it via any of the following:
>
> 1. **System Settings**: System Settings -> Privacy & Security -> Security, scroll to the bottom and click "Open Anyway".
> 2. **Right-click open**: Find Repaste in the Applications folder in Finder, right-click -> Open, then click "Open" in the confirmation dialog.
> 3. **Remove the quarantine attribute in Terminal**:
>    ```bash
>    xattr -cr /Applications/Repaste.app
>    ```
>    Then double-click to open it again.

### First Launch

A short onboarding guide appears on first launch:

| Step | Content |
| --- | --- |
| 1. Welcome to Repaste | Choose the default tab shown when opening the history |
| 2. Privacy & local storage | All records stay on this Mac; password-like content is skipped automatically |
| 3. Give it a try | Slide the mouse to the notch at the top of the screen; done once the panel appears (skippable) |

Onboarding never asks for any system permissions. In the default mode, selecting an entry writes it back to the clipboard — just press `⌘V` in any app to paste.

Only if you enable "Paste directly into the active app" (auto-paste) in Settings will you be prompted for Accessibility permission: go to **System Settings -> Privacy & Security -> Accessibility** and toggle **Repaste** on. Declining simply falls back to the default copy-only behavior.

### Option 2: Build from Source (developers)

Requirements: Xcode 16+, macOS 15+ SDK. The project has **zero third-party dependencies** — no Swift Package / CocoaPods resolution needed.

```bash
git clone https://github.com/klosexf/Repaste.git
cd Repaste
open Repaste/Repaste.xcodeproj   # Press ⌘R in Xcode to run
```

Or build from the command line:

```bash
xcodebuild -project Repaste/Repaste.xcodeproj -scheme Repaste build
```

## Keyboard Shortcuts

| Key | Action |
| --- | --- |
| `⌥⇧V` | Show / hide the panel |
| `↑` `↓` | Select entry |
| `⏎` | Use (writes to clipboard, panel closes) |
| `⌘⏎` | Open link |
| `⌘G` | Save to template group |
| `⌫` | Delete entry |
| `esc` | Close panel |

## Privacy

- **Fully local storage** — no account, no upload, no sync; history and images never leave your Mac
- **Passwords skipped automatically** — password-type content (ConcealedType) copied from 1Password / Keychain is never stored
- **Zero permissions by default** — no system authorization required; only the optional "paste into the active app" feature needs Accessibility
- **You control the data** — images are purged automatically after 7 days (TTL); view the storage overview, clear history or images in Settings

## Technical Architecture

Pure native macOS development: SwiftUI builds the UI, AppKit hosts the windows (the main panel is a borderless NSPanel that never steals focus).

| Layer | Technology |
| --- | --- |
| UI views | SwiftUI (panel, cards, settings, onboarding) |
| Window layer | AppKit (NSPanel / NSWindow) |
| Data layer | SwiftData (Clip / TemplateGroup, backed by SQLite) + UserDefaults |
| State management | Observation (`@Observable`) |
| Global hotkey | Carbon RegisterEventHotKey (zero permissions) |
| Clipboard polling | NSPasteboard.changeCount polling (idle CPU ≈ 0) |
| Dependencies | None |

```text
Repaste/
├── RepasteApp.swift            # App entry & window bridge
├── DesignTokens.swift          # Design system (matte black + brand purple)
├── Models/                     # SwiftData models: Clip, TemplateGroup
├── Services/                   # Clipboard engine
│   ├── ClipboardMonitor.swift  #   Capture, type detection, 200-entry eviction, password skip
│   ├── ClipboardStore.swift    #   History queries, filtering, pinning, deletion
│   ├── ImageStore.swift        #   Image persistence & TTL cleanup
│   ├── AutoPaster.swift        #   Paste into frontmost app (optional, needs Accessibility)
│   └── SettingsStore.swift     #   Settings (applied instantly)
├── Panel/                      # Main panel (shared by notch dropdown & hotkey summon)
│   ├── PanelView.swift         #   Search, tabs, source bar, card list
│   └── ClipMoreMenu.swift      #   ⋮ menu (composed per content type)
├── Settings/                   # Settings window: General / Summon / History & Privacy
├── Onboarding/                 # First-launch onboarding (3 steps, zero permissions)
└── Summon/                     # Summon system
    ├── HotZoneWatcher.swift    #   Notch hot-zone state machine (anti-false-trigger core)
    ├── HotKeyManager.swift     #   ⌥⇧V global hotkey
    └── CapsuleController.swift #   Capsule fallback for non-notch / external screens
```

## Roadmap

- [ ] iCloud / multi-device sync
- [ ] Template variables & placeholders (`{{date}}`, `{{clipboard}}`)
- [ ] Right-click context menus & batch actions
- [ ] Link preview cards (title & thumbnail)
- [ ] Image OCR, drag-out of the panel
- [ ] Sparkle auto-update

## License

[MIT](LICENSE) © 2026 陈晓峰

---

<p align="center">Hover the notch, and give it a try.</p>
