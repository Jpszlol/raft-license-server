//
//  Raft_BrowserApp.swift
//  Raft Browser
//
//  Created by 3 on 4/25/25.
//

import SwiftUI
import AppKit
import Carbon

/// Floating “HUD” panel that mimics FloatBrowse.HudPanel
/// It advertises itself as an AXSystemDialog, floats at `.statusBar` level,
/// and doesn’t steal main‑window status.
final class HudPanel: NSPanel {

    /// Designated‑initializer override
    override init(contentRect: NSRect,
                  styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: styleMask,
                   backing: backing,
                   defer: flag)
        configureHUDStyle()
    }

    /// Convenience wrapper that supplies FloatBrowse‑like defaults
    convenience init(contentRect: NSRect) {
        let defaultMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        self.init(contentRect: contentRect,
                  styleMask: defaultMask,
                  backing: .buffered,
                  defer: false)
    }

    @available(*, unavailable, message: "Not implemented")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Behaviour identical to FloatBrowse.HudPanel
    private func configureHUDStyle() {
        // “AXSystemDialog” isn’t exposed as a typed constant, so use the raw value
        setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: "AXSystemDialog"))
        setAccessibilityRole(.window)          // AXWindow

        becomesKeyOnlyIfNeeded = true
        if #available(macOS 11.0, *) { tabbingMode = .disallowed }

        isFloatingPanel = true
        level = .statusBar                     // floats above normal windows/menu extras
        hidesOnDeactivate = false

        collectionBehavior = [.canJoinAllSpaces,
                              .fullScreenAuxiliary,
                              .stationary,
                              .ignoresCycle]

        isOpaque        = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .visible

        isMovableByWindowBackground = true
    }

    // Don’t become main, but allow key focus for controls
    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Create the floating panel
        panel = makePanel()
        panel?.makeKeyAndOrderFront(nil)

        // Configure the status‑bar item
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Raft Browser")
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        statusItem = item

        // ---- System‑wide ⌘‑2 hot‑key (Carbon) ----
        let id = EventHotKeyID(signature: OSType(UInt32(bigEndian: 0x52414654)), // 'RAFT'
                               id: 1)
        // kVK_ANSI_2 = 0x1F; cmdKey = ⌘
        RegisterEventHotKey(UInt32(kVK_ANSI_2),
                            UInt32(cmdKey),
                            id,
                            GetEventDispatcherTarget(),
                            0,
                            &hotKeyRef)

        // Handler: when ⌘‑2 is pressed anywhere, toggle panel
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
            guard let ptr = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            delegate.togglePanel(nil)
            return noErr
        }, 1, &spec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), nil)
    }

    /// Hide if visible; otherwise (re‑show and activate Raft
    @objc func togglePanel(_ sender: Any?) {

        // If panel was deallocated for some reason, recreate it
        if panel == nil || panel?.contentViewController == nil {
            panel = makePanel()
        }
        guard let pnl = panel else { return }

        if pnl.isVisible {
            pnl.orderOut(nil)                        // hide
        } else {
            pnl.orderFrontRegardless()               // show
            NSApp.activate(ignoringOtherApps: true)  // bring Raft forward
        }
    }

    // MARK: - Panel builder
    private func makePanel() -> NSPanel {
        let controller = NSHostingController(rootView: ContentView())
        // Use our custom HUD panel subclass that mirrors FloatBrowse behaviour
        let p = HudPanel(contentRect: NSRect(x: 300, y: 500, width: 900, height: 550))
        // p.setAccessibilitySubrole(NSAccessibility.Subrole.systemDialog)
        // p.setAccessibilityRole(.window)   // Role stays AXWindow; subrole = AXSystemDialog

        p.becomesKeyOnlyIfNeeded = true
        if #available(macOS 11.0, *) {
            p.tabbingMode = .disallowed
        }

        // p.isFloatingPanel = true
        // p.level = .statusBar            // Float at the same level ChatGPT’s launcher uses
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .visible
        p.collectionBehavior = [.canJoinAllSpaces,
                                .fullScreenAuxiliary,
                                .stationary,
                                .ignoresCycle]

        p.hidesOnDeactivate = false
        p.isOpaque          = false
        p.backgroundColor   = .clear
        p.hasShadow         = true

        // Rounded corners & dark blur like ChatGPT’s quick‑open bar
        if let cv = p.contentView {
            cv.wantsLayer           = true
            cv.layer?.cornerRadius  = 22
            cv.layer?.masksToBounds = true

            let blur = NSVisualEffectView(frame: cv.bounds)
            blur.autoresizingMask = [.width, .height]
            blur.material         = .hudWindow
            blur.state            = .active
            cv.addSubview(blur, positioned: .below, relativeTo: nil)
        }

        if #available(macOS 13, *) { p.toolbarStyle = .unifiedCompact }
        p.isMovableByWindowBackground = true

        p.contentViewController = controller
        return p
    }
}

@main
struct RaftBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands { }
    }
}
