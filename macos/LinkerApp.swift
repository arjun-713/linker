// LinkerApp.swift — Linker menu bar app for macOS 13+
//
// A keyboard-first panel: click the link status icon (or ⌘⇧L anywhere), type to
// filter, ⏎ or click copies to the pasteboard. Reads the SAME store as the CLI:
// ~/.config/linker/links.json (read-only — editing stays in the terminal).
//
// Build: ./build.sh          (see build.sh / README.md)

import AppKit
import Carbon
import ServiceManagement
import SwiftUI

// MARK: - Store model (matches the CLI's links.json schema exactly)

struct StoredLink: Codable {
    let alias: String
    let url: String
    let tags: [String]?
    let note: String?
    let copyCount: Int?
    let lastCopied: String?

    enum CodingKeys: String, CodingKey {
        case alias, url, tags, note
        case copyCount = "copy_count"
        case lastCopied = "last_copied"
    }
}

private struct StoreFile: Codable {
    let version: Int?
    let links: [StoredLink]?
}

struct Link: Identifiable, Hashable {
    let alias: String
    let url: String
    let tags: [String]
    let note: String
    var id: String { alias }

    var displayURL: String {
        for prefix in ["https://", "http://"] where url.hasPrefix(prefix) {
            return String(url.dropFirst(prefix.count))
        }
        return url
    }
}

// MARK: - Fuzzy scoring (same rewards as the CLI: word starts + consecutive runs)

func linkScore(_ needle: String, _ haystack: String) -> Int? {
    if needle.isEmpty { return 0 }
    let n = Array(needle.lowercased())
    let h = Array(haystack.lowercased())
    if n.count > h.count { return nil }
    var total = 0
    var prev = -1
    for ch in n {
        guard let idx = firstIndex(of: ch, in: h, after: prev) else { return nil }
        var pts = 1
        if prev >= 0 && idx == prev + 1 { pts += 1 }
        if idx == 0 || "-_/.@ ".contains(h[idx - 1]) { pts += 3 }
        total += pts
        prev = idx
    }
    if h.starts(with: n) { total += 5 }
    if n.count == h.count { total += 2 }
    return total
}

private func firstIndex(of ch: Character, in chars: [Character], after i: Int) -> Int? {
    guard i + 1 < chars.count else { return nil }
    for j in (i + 1)..<chars.count where chars[j] == ch { return j }
    return nil
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Panel model

@MainActor
final class PanelModel: ObservableObject {
    @Published var links: [Link] = []
    @Published var query: String = "" {
        didSet { selected = 0 }
    }
    @Published var selected: Int = 0
    @Published var selectedTag: String? = nil { didSet { selected = 0 } }
    @Published var toast: String?
    @Published var actionError: String?
    @Published var loadError: String?
    @Published var copiedAlias: String?
    @Published var focusToken: Int = 0

    var storeURL: URL {
        if let path = ProcessInfo.processInfo.environment["LINKER_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/linker/links.json")
    }

    func reload() {
        loadError = nil
        actionError = nil
        toast = nil
        copiedAlias = nil
        selected = 0
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            links = []
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let file = try JSONDecoder().decode(StoreFile.self, from: data)
            links = (file.links ?? []).compactMap { stored in
                guard !stored.alias.isEmpty, !stored.url.isEmpty else { return nil }
                return Link(alias: stored.alias, url: stored.url,
                            tags: Array(Set(stored.tags ?? [])).sorted(), note: stored.note ?? "")
            }
        } catch {
            links = []
            loadError = "Linker couldn’t read links.json. Check the file, then try again."
        }
        if let tag = selectedTag, !tags.contains(tag) { selectedTag = nil }
    }

    var tags: [String] { Array(Set(links.flatMap(\.tags))).sorted() }

    var selectedLink: Link? { matches[safe: selected] }

    func clearFilters() {
        query = ""
        selectedTag = nil
    }

    var matches: [Link] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = links.filter { link in
            guard let tag = selectedTag else { return true }
            return link.tags.contains(tag)
        }
        guard !q.isEmpty else { return candidates.sorted { $0.alias < $1.alias } }
        var scored: [(Int, Link)] = []
        for link in candidates {
            if let aliasScore = linkScore(q, link.alias) {
                scored.append((aliasScore * 3, link))
                continue
            }
            var best: Int?
            for blob in [link.url, link.tags.joined(separator: ","), link.note] where !blob.isEmpty {
                if let s = linkScore(q, blob) { best = max(best ?? 0, s) }
            }
            if let best { scored.append((best, link)) }
        }
        return scored.sorted { lhs, rhs in
            lhs.0 != rhs.0 ? lhs.0 > rhs.0 : lhs.1.alias < rhs.1.alias
        }.map { $0.1 }
    }

    func copy(_ link: Link) {
        guard copiedAlias == nil else { return }
        actionError = nil
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(link.url, forType: .string) else {
            actionError = "Couldn’t copy. Press Return to try again."
            return
        }
        copiedAlias = link.alias
        toast = "Copied \(link.alias) to clipboard"
    }

    func open(_ link: Link) -> Bool {
        guard let url = URL(string: link.url), NSWorkspace.shared.open(url) else {
            actionError = "Couldn’t open this URL. You can still copy it."
            return false
        }
        return true
    }
}

// MARK: - Panel window

final class LinkerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController {
    static let shared = PanelController()

    let model = PanelModel()
    weak var anchorButton: NSStatusBarButton?

    private var panel: LinkerPanel!
    private var contentInstalled = false
    private var monitorsInstalled = false
    fileprivate var outsideClickMonitor: Any?
    fileprivate var keyDownMonitor: Any?

    private init() {
        panel = LinkerPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func ensureContent() {
        guard !contentInstalled else { return }
        contentInstalled = true
        let hosting = NSHostingView(rootView: LinkerPanelView(model: model) {
            PanelController.shared.hide()
        })
        panel.contentView = hosting
    }

    func show() {
        ensureContent()
        model.reload()
        model.toast = nil
        model.clearFilters()
        model.focusToken += 1
        positionUnderAnchor()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func positionUnderAnchor() {
        let width = PanelMetrics.width
        let height = PanelMetrics.height
        let screen = anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        var origin = NSPoint(
            x: (screen?.frame.midX ?? 0) - width / 2,
            y: (screen?.frame.maxY ?? 720) - height - 60
        )
        if let button = anchorButton, let window = button.window {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: frame.midX - width / 2, y: frame.minY - height - 6)
        }
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    func installMonitors() {
        guard !monitorsInstalled else { return }
        monitorsInstalled = true

        // hide when clicking anywhere outside the panel (except the status icon)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let location = event.locationInWindow  // screen coordinates for global monitors
            if let button = self.anchorButton, let window = button.window {
                let anchorFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                if anchorFrame.contains(location) { return }
            }
            if !panel.frame.contains(location) { self.hide() }
        }

        // esc / arrows / return while the panel is key
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible, event.window === panel else {
                return event
            }
            switch event.keyCode {
            case 53:  // esc
                self.hide()
                return nil
            case 125:  // down
                let lastIndex = max(self.model.matches.count - 1, 0)
                self.model.selected = min(self.model.selected + 1, lastIndex)
                return nil
            case 126:  // up
                self.model.selected = max(self.model.selected - 1, 0)
                return nil
            case 36:  // return — copy the selected row
                if let link = self.model.matches[safe: self.model.selected] {
                    if event.modifierFlags.contains(.command) {
                        if self.model.open(link) { self.hide() }
                    } else {
                        self.model.copy(link)
                    }
                }
                return nil
            case 15 where event.modifierFlags.contains(.command):  // ⌘R — reload
                self.model.reload()
                return nil
            case 3 where event.modifierFlags.contains(.command):  // ⌘F — search
                self.model.toast = nil
                self.model.copiedAlias = nil
                self.model.actionError = nil
                self.model.focusToken += 1
                return nil
            default:
                return event
            }
        }
    }
}

// MARK: - App delegate: status item, menu, global hotkey

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var handlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        PanelController.shared.anchorButton = statusItem.button
        PanelController.shared.installMonitors()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let outside = PanelController.shared.outsideClickMonitor {
            NSEvent.removeMonitor(outside)
        }
        if let key = PanelController.shared.keyDownMonitor {
            NSEvent.removeMonitor(key)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Linker")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp || event?.type == .otherMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if rightClick {
            showMenu()
        } else {
            PanelController.shared.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        if #available(macOS 13.0, *) {
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            login.isHidden = true
        }
        menu.addItem(login)
        let openStore = NSMenuItem(title: "Open links.json", action: #selector(openStoreFile), keyEquivalent: "")
        openStore.target = self
        menu.addItem(openStore)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Linker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // registration can fail when the app is not in /Applications — ignore
            }
        }
    }

    @objc private func openStoreFile() {
        PanelController.shared.hide()
        NSWorkspace.shared.open(PanelController.shared.model.storeURL)
    }

    /// ⌘⇧L anywhere toggles the panel. Change the key here if you prefer another one.
    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                AppDelegate.shared?.panelController.toggle()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
        var hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4B52), id: 1)  // 'LNKR'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L),              // L
            UInt32(cmdKey | shiftKey),       // ⌘⇧
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

extension AppDelegate {
    var panelController: PanelController { PanelController.shared }
}

// MARK: - main

@main
final class LinkerMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        app.run()
    }
}
