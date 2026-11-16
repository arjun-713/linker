// LinkerApp.swift — Linker menu bar app for macOS 13+
//
// A keyboard-first panel: click the link status icon (or ⌘⇧L anywhere), type to
// filter, ⏎ or click copies to the pasteboard. Shares the SAME store as the CLI:
// ~/.config/linker/links.json — ⌘N (or the + button) adds a link right in the
// panel, written in the CLI's exact file format; edits and removals stay in the
// terminal.
//
// On macOS 26+ the panel is drawn with Apple's Liquid Glass; older systems get
// a solid panel with the same layout (see LinkerViews.swift).
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
    var copyCount: Int = 0
    var lastCopied: String = ""
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

enum SortMode: String {
    case alpha, recent
}

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
    @Published var dismissOnToast = true

    @Published var sortMode: SortMode = UserDefaults.standard.string(forKey: "linker.sortMode") == "recent" ? .recent : .alpha

    // Add / edit state (⌘N / + in the header, or right-click menu → Add Link…)
    @Published var addMode = false
    @Published var editingAlias: String?  // nil while adding, set while editing
    @Published var addFocusToken: Int = 0
    @Published var draftAlias = "" { didSet { validateAliasLive() } }
    @Published var draftURL = "" { didSet { urlError = nil; addError = nil } }
    @Published var draftTags = "" { didSet { addError = nil } }
    @Published var draftNote = "" { didSet { addError = nil } }
    @Published var aliasError: String?
    @Published var urlError: String?
    @Published var addError: String?
    // Delete undo (⌘Z while the "Deleted …" toast is showing)
    var pendingDeleteRecord: [String: Any]?

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
                            tags: Array(Set(stored.tags ?? [])).sorted(), note: stored.note ?? "",
                            copyCount: stored.copyCount ?? 0, lastCopied: stored.lastCopied ?? "")
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
        guard !q.isEmpty else {
            switch sortMode {
            case .alpha:
                return candidates.sorted { $0.alias < $1.alias }
            case .recent:
                // CLI `recent` order: last copied first, never-copied last,
                // alias order as the stable tiebreak.
                return candidates.sorted {
                    if $0.lastCopied != $1.lastCopied { return $0.lastCopied > $1.lastCopied }
                    return $0.alias < $1.alias
                }
            }
        }
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
        try? writeCopyStats(alias: link.alias)  // best effort — never blocks the copy
        copiedAlias = link.alias
        toast = "Copied \(link.alias) to clipboard"
    }

    /// Copy from the status menu without opening the panel.
    func quickCopy(alias: String) {
        guard let link = links.first(where: { $0.alias == alias }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(link.url, forType: .string) else { return }
        try? writeCopyStats(alias: link.alias)
        toast = "Copied \(link.alias) to clipboard"
    }

    func open(_ link: Link) -> Bool {
        guard let url = URL(string: link.url), NSWorkspace.shared.open(url) else {
            actionError = "Couldn’t open this URL. You can still copy it."
            return false
        }
        return true
    }

    // MARK: add-link (panel-side authoring, CLI-compatible store writes)

    var canSubmitAdd: Bool {
        !draftAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleSort() {
        sortMode = sortMode == .alpha ? .recent : .alpha
        UserDefaults.standard.set(sortMode.rawValue, forKey: "linker.sortMode")
    }

    func openAdd() {
        editingAlias = nil
        clearFilters()
        toast = nil
        copiedAlias = nil
        actionError = nil
        clearDrafts()
        // A URL already on the pasteboard pre-fills the form.
        if let board = NSPasteboard.general.string(forType: .string),
           let cleaned = LinkerValidation.url(board), cleaned.count <= 500 {
            draftURL = cleaned
        }
        addMode = true
        addFocusToken += 1
    }

    func openEdit(_ link: Link) {
        editingAlias = link.alias
        clearFilters()
        toast = nil
        copiedAlias = nil
        actionError = nil
        clearDrafts()
        draftAlias = link.alias
        draftURL = link.url
        draftTags = link.tags.joined(separator: ", ")
        draftNote = link.note
        addMode = true
        addFocusToken += 1
    }

    func cancelAdd() {
        addMode = false
        editingAlias = nil
        clearDrafts()
        focusToken += 1  // hand keyboard focus back to search
    }

    private func clearDrafts() {
        draftAlias = ""
        draftURL = ""
        draftTags = ""
        draftNote = ""
        aliasError = nil
        urlError = nil
        addError = nil
    }

    /// Live alias feedback while typing: format and duplicates surface
    /// immediately instead of only on submit.
    private func validateAliasLive() {
        aliasError = nil
        addError = nil
        let alias = draftAlias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !alias.isEmpty else { return }
        if LinkerValidation.alias(alias) == nil {
            aliasError = "Use letters, digits, “-” or “_” (max 32, start with a letter or digit)."
        } else if links.contains(where: { $0.alias == alias && $0.alias != editingAlias }) {
            aliasError = "“\(alias)” already exists — pick another alias."
        }
    }

    func submitAdd() {
        aliasError = nil
        urlError = nil
        addError = nil

        let alias = draftAlias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let validAlias = LinkerValidation.alias(alias) else {
            aliasError = "Use letters, digits, “-” or “_” (max 32, start with a letter or digit)."
            return
        }
        guard let url = LinkerValidation.url(draftURL) else {
            urlError = "Add a scheme — https://, ssh://, mailto:…"
            return
        }
        let editing = editingAlias
        if validAlias != editing, links.contains(where: { $0.alias == validAlias }) {
            addError = "“\(validAlias)” already exists — pick another alias."
            return
        }
        let tags = LinkerValidation.tags(draftTags)
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let editing {
                try writeUpdatedLink(originalAlias: editing, alias: validAlias,
                                     url: url, tags: tags, note: note)
            } else {
                try writeNewLink(alias: validAlias, url: url, tags: tags, note: note)
            }
        } catch {
            addError = "Couldn’t save: \(error.localizedDescription)"
            return
        }

        reload()
        clearDrafts()
        addMode = false
        editingAlias = nil
        if let idx = matches.firstIndex(where: { $0.alias == validAlias }) { selected = idx }
        dismissOnToast = false  // stay open so several links can be added in a row
        toast = editing == nil ? "Added \(validAlias) to your links" : "Updated \(validAlias)"
    }

    func delete(_ link: Link) {
        do {
            try writeDeletedLink(alias: link.alias)
        } catch {
            actionError = "Couldn’t delete \(link.alias): \(error.localizedDescription)"
            return
        }
        reload()
        selected = min(selected, max(matches.count - 1, 0))
        dismissOnToast = false
        toast = "Deleted \(link.alias) — ⌘Z to undo"
    }

    func undoDelete() {
        guard let record = pendingDeleteRecord else { return }
        do {
            try writeRestoredLink(record)
        } catch {
            actionError = "Couldn’t undo: \(error.localizedDescription)"
            return
        }
        pendingDeleteRecord = nil
        let alias = record["alias"] as? String ?? ""
        reload()
        if let idx = matches.firstIndex(where: { $0.alias == alias }) { selected = idx }
        toast = "Restored \(alias)"
    }

    /// Runs one mutation against the raw links.json records and writes the file
    /// in the CLI's exact schema: {"version": 1, "links": [...]} — alias-sorted,
    /// atomic write, 0600. Existing records (and fields the app doesn't model)
    /// are preserved untouched.
    private func withStore(_ transform: (inout [[String: Any]]) throws -> Void) throws {
        let fm = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        var payload: [String: Any] = ["version": 1, "links": [[String: Any]]()]
        if fm.fileExists(atPath: storeURL.path) {
            let data = try Data(contentsOf: storeURL)
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = object
                if payload["links"] == nil { payload["links"] = [[String: Any]]() }
            }
        }
        var records = payload["links"] as? [[String: Any]] ?? []
        try transform(&records)
        records.sort { ($0["alias"] as? String ?? "") < ($1["alias"] as? String ?? "") }
        payload["version"] = 1
        payload["links"] = records

        var data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        data.append(Data("\n".utf8))
        let temporary = directory.appendingPathComponent(".links-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fm.fileExists(atPath: storeURL.path) {
            _ = try fm.replaceItemAt(storeURL, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: storeURL)
        }
    }

    private static func recordIndex(of alias: String, in records: [[String: Any]]) -> Int? {
        records.firstIndex { ($0["alias"] as? String)?.lowercased() == alias.lowercased() }
    }

    private func writeNewLink(alias: String, url: String, tags: [String], note: String) throws {
        try withStore { records in
            if Self.recordIndex(of: alias, in: records) != nil {
                throw NSError(domain: "dev.arjun.linker", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "“\(alias)” already exists in links.json"])
            }
            let stamp = LinkerValidation.isoStamp()
            var record: [String: Any] = [
                "alias": alias,
                "url": url,
                "tags": tags,
                "created_at": stamp,
                "updated_at": stamp,
                "copy_count": 0,
                "last_copied": "",
            ]
            if !note.isEmpty { record["note"] = note }
            records.append(record)
        }
    }

    private func writeUpdatedLink(originalAlias: String, alias: String, url: String,
                                  tags: [String], note: String) throws {
        try withStore { records in
            guard let idx = Self.recordIndex(of: originalAlias, in: records) else {
                throw NSError(domain: "dev.arjun.linker", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "“\(originalAlias)” is no longer in links.json"])
            }
            var record = records[idx]  // preserves created_at, copy stats, unknown fields
            record["alias"] = alias
            record["url"] = url
            record["tags"] = tags
            record["updated_at"] = LinkerValidation.isoStamp()
            if note.isEmpty {
                record.removeValue(forKey: "note")
            } else {
                record["note"] = note
            }
            records[idx] = record
        }
    }

    private func writeDeletedLink(alias: String) throws {
        try withStore { records in
            guard let idx = Self.recordIndex(of: alias, in: records) else {
                throw NSError(domain: "dev.arjun.linker", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "“\(alias)” is no longer in links.json"])
            }
            pendingDeleteRecord = records.remove(at: idx)
        }
    }

    private func writeRestoredLink(_ record: [String: Any]) throws {
        try withStore { records in
            let alias = record["alias"] as? String ?? ""
            if Self.recordIndex(of: alias, in: records) == nil {
                records.append(record)
            }
        }
    }

    private func writeCopyStats(alias: String) throws {
        let stamp = LinkerValidation.isoStamp()
        try withStore { records in
            guard let idx = Self.recordIndex(of: alias, in: records) else { return }
            let count = (records[idx]["copy_count"] as? Int) ?? 0
            records[idx]["copy_count"] = count + 1
            records[idx]["last_copied"] = stamp
            records[idx]["updated_at"] = stamp
        }
    }
}

/// "now / 5m / 3h / 2d"-style relative age for a last_copied ISO stamp.
func relativeCopyTime(_ stamp: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    guard let date = parser.date(from: stamp) else { return "" }
    let seconds = Date().timeIntervalSince(date)
    let ago = max(0, Int(seconds))
    if seconds < 0 { return "now" }
    if ago < 10 { return "now" }
    if ago < 3600 { return "\(ago / 60)m" }
    if ago < 86_400 { return "\(ago / 3_600)h" }
    return "\(ago / 86_400)d"
}

// MARK: - Input validation (mirrors the CLI's rules exactly)
enum LinkerValidation {
    /// CLI: ALIAS_RE = ^[a-z0-9][a-z0-9_-]{0,31}$
    static func alias(_ raw: String) -> String? {
        let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !alias.isEmpty, alias.count <= 32 else { return nil }
        let bodyOK = alias.allSatisfy { ch in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "-" || ch == "_"
        }
        guard bodyOK, let first = alias.first, first.isASCII && (first.isLetter || first.isNumber) else {
            return nil
        }
        return alias
    }

    /// CLI `clean_url`: git@host:path becomes https://host/path, a bare domain
    /// gets https:// prepended, and a scheme is otherwise required.
    static func url(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return nil }

        // git@github.com:owner/repo.git → https://github.com/owner/repo
        if value.lowercased().hasPrefix("git@"),
           let at = value.firstIndex(of: "@"),
           let colon = value.firstIndex(of: ":"),
           colon > at {
            let host = String(value[value.index(after: at)..<colon])
            var path = String(value[value.index(after: colon)...])
            if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
            if !host.isEmpty, !path.isEmpty, !path.contains("://") {
                value = "https://\(host)/\(path)"
            }
        }

        // scheme://rest
        if let colon = value.firstIndex(of: ":") {
            let scheme = String(value[..<colon])
            let rest = String(value[value.index(after: colon)...])
            let schemeOK = !scheme.isEmpty
                && scheme.first!.isLetter
                && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
            if schemeOK, rest.hasPrefix("//"), rest.count > 3 {
                return value
            }
            return nil  // has a colon but not a valid scheme — reject like the CLI
        }

        // bare domain: https:// gets prepended (friendlier than the CLI's error)
        if value.contains(".") {
            return "https://" + value
        }
        return nil
    }

    /// CLI `parse_tags`: comma-separated, trimmed, lowercased, deduped in order.
    static func tags(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for part in raw.split(separator: ",") {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    /// Same shape as the CLI: datetime.now(timezone.utc).isoformat(timespec="seconds")
    static func isoStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+00:00'"
        return formatter.string(from: Date())
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
        if #available(macOS 26.0, *) {
            panel.hasShadow = false  // Liquid Glass carries its own depth; the
                                     // window shadow only adds a square outline
        } else {
            panel.hasShadow = true
        }
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
        if model.addMode { model.addFocusToken += 1 }
        positionUnderAnchor()
        panel.orderFrontRegardless()
        // Quick fade-in from the status icon — reads as glass condensing.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Show the panel with the add-link form open (right-click menu → Add Link…).
    func showAdd() {
        show()
        model.openAdd()
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
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
            case 53:  // esc — exit add mode first, otherwise hide the panel
                if self.model.addMode {
                    self.model.cancelAdd()
                } else {
                    self.hide()
                }
                return nil
            case 125, 126:  // down / up — list navigation only
                guard !self.model.addMode else { return event }
                if event.keyCode == 125 {
                    let lastIndex = max(self.model.matches.count - 1, 0)
                    self.model.selected = min(self.model.selected + 1, lastIndex)
                } else {
                    self.model.selected = max(self.model.selected - 1, 0)
                }
                return nil
            case 36:  // return — in add mode the text fields handle it (save)
                guard !self.model.addMode else { return event }
                if let link = self.model.matches[safe: self.model.selected] {
                    if event.modifierFlags.contains(.command) {
                        if self.model.open(link) { self.hide() }
                    } else {
                        self.model.copy(link)
                    }
                }
                return nil
            case 15 where event.modifierFlags.contains(.command):  // ⌘R — reload
                guard !self.model.addMode else { return event }
                self.model.reload()
                return nil
            case 3 where event.modifierFlags.contains(.command):  // ⌘F — search
                guard !self.model.addMode else { return event }
                self.model.toast = nil
                self.model.copiedAlias = nil
                self.model.actionError = nil
                self.model.focusToken += 1
                return nil
            case 14 where event.modifierFlags.contains(.command):  // ⌘E — edit selected
                guard !self.model.addMode else { return event }
                if let link = self.model.matches[safe: self.model.selected] {
                    self.model.openEdit(link)
                }
                return nil
            case 51 where event.modifierFlags.contains(.command):  // ⌘⌫ — delete selected
                guard !self.model.addMode else { return event }
                if let link = self.model.matches[safe: self.model.selected] {
                    self.model.delete(link)
                }
                return nil
            case 6 where event.modifierFlags.contains(.command):  // ⌘Z — undo delete
                guard !self.model.addMode else { return event }
                self.model.undoDelete()
                return nil
            case 1 where event.modifierFlags.contains(.command):  // ⌘S — toggle sort
                guard !self.model.addMode else { return event }
                self.model.toggleSort()
                return nil
            case 45 where event.modifierFlags.contains(.command):  // ⌘N — add a link
                if self.model.addMode {
                    self.model.addFocusToken += 1
                } else {
                    self.model.openAdd()
                }
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
        let add = NSMenuItem(title: "Add Link…", action: #selector(addLinkFromMenu), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let topLinks = PanelController.shared.model.links
            .sorted { $0.alias < $1.alias }.prefix(5)
        if !topLinks.isEmpty {
            menu.addItem(.separator())
            for link in topLinks {
                let item = NSMenuItem(title: "Copy \(link.alias)", action: #selector(quickCopyItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = link.alias
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
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

    @objc private func quickCopyItem(_ sender: NSMenuItem) {
        guard let alias = sender.representedObject as? String else { return }
        PanelController.shared.model.quickCopy(alias: alias)
    }

    @objc private func addLinkFromMenu() {
        PanelController.shared.showAdd()
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
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4B52), id: 1)  // 'LNKR'
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
