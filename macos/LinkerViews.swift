// Native presentation. On macOS 26+ the panel renders in Apple's Liquid Glass
// (glassEffect / GlassButtonStyle); macOS 13–25 gets a solid panel with the
// same layout. The add-link form writes links.json in the CLI's exact format.
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 440
    static let height: CGFloat = 568
}

// Semantic, appearance-adaptive colors. Over Liquid Glass, text uses the
// system's full-contrast label hierarchy and fills are translucent tints that
// pick up whatever is behind the glass — no opaque greys.
private struct PanelPalette {
    var surface: Color { Color(nsColor: .windowBackgroundColor) }
    var ink: Color { Color.primary }
    var muted: Color { Color.secondary }
    var faint: Color { Color(nsColor: .tertiaryLabelColor) }
    var field: Color { Color.primary.opacity(0.08) }
    var selected: Color { Color.accentColor.opacity(0.18) }
    var line: Color { Color.primary.opacity(0.15) }
    var control: Color { Color.accentColor }
    var success: Color { Color(nsColor: .systemGreen) }
    var danger: Color { Color(nsColor: .systemRed) }
}

// MARK: - Liquid Glass chrome (with a solid fallback for macOS 13–25)

private struct PanelGlass: ViewModifier {

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            let palette = PanelPalette()
            content
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
        }
    }
}

private struct FieldGlass: ViewModifier {
    var focused: Bool = false
    var error: String? = nil

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(error == nil ? Color.clear : PanelPalette().danger.opacity(0.7),
                            lineWidth: 1))
        } else {
            let palette = PanelPalette()
            content
                .background(palette.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(error != nil ? palette.danger.opacity(0.7)
                                          : (focused ? palette.control : palette.line),
                            lineWidth: 1))
        }
    }
}

private struct FooterGlass: ViewModifier {

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .overlay(alignment: .top) {
                    Rectangle().fill(PanelPalette().line.opacity(0.45)).frame(height: 1)
                }
        } else {
            let palette = PanelPalette()
            content
                .background(palette.field)
                .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
        }
    }
}

/// A pill button: `.buttonStyle(.glass)` on macOS 26+, plain on older systems.
private struct GlassPill<Label: View>: View {
    let action: () -> Void
    var disabled: Bool = false
    @ViewBuilder var label: () -> Label

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action, label: label)
                .buttonStyle(.glass)
                .disabled(disabled)
        } else {
            Button(action: action, label: label)
                .buttonStyle(.plain)
                .disabled(disabled)
        }
    }
}

/// A small icon button: glass on macOS 26+, plain square hit target otherwise.
private struct IconGlassButton: View {
    let system: String
    let help: String
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: system)
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.glass)
            .help(help)
        } else {
            let palette = PanelPalette()
            Button(action: action) {
                Image(systemName: system)
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        let palette = PanelPalette()
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(palette.muted)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(palette.field)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private struct LinkRow: View {
    let link: Link
    let selected: Bool
    let copied: Bool
    let showRecency: Bool
    let onCopy: () -> Void
    var onOpen: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        let palette = PanelPalette()
        Button(action: onCopy) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(palette.muted)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.alias)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                    Text(link.displayURL)
                        .font(.system(size: 12))
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showRecency, !link.lastCopied.isEmpty {
                    Text(relativeCopyTime(link.lastCopied))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(palette.faint)
                }
                if link.copyCount > 0 {
                    Text("\(link.copyCount)×")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(palette.faint)
                }
                if let tag = link.tags.first {
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.field)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: 88)
                }
                Image(systemName: copied ? "checkmark" : "return")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(copied ? palette.success : palette.muted)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 12)
            .frame(height: 60)
            .background(selected ? palette.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(([link.url] + link.tags + [link.note]).filter { !$0.isEmpty }.joined(separator: " · "))
        .contextMenu {
            Button("Copy URL") { onCopy() }.keyboardShortcut(.return, modifiers: [])
            Button("Open in Browser") { onOpen() }.keyboardShortcut(.return, modifiers: .command)
            Divider()
            Button("Edit…") { onEdit() }.keyboardShortcut("e", modifiers: .command)
            Button("Delete", role: .destructive) { onDelete() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .accessibilityLabel("Copy \(link.alias)")
        .accessibilityValue(link.url)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Add-link form

enum AddFieldKind {
    case alias, url, tags, note
}

private struct AddField: View {
    let icon: String
    let title: String
    @Binding var text: String
    let placeholder: String
    let field: AddFieldKind
    var focus: FocusState<AddFieldKind?>.Binding
    let onSubmit: () -> Void
    var error: String? = nil

    var body: some View {
        let palette = PanelPalette()
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(error == nil ? palette.muted : palette.danger)
                    .frame(width: 16)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(palette.ink)
                    .focused(focus, equals: field)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .modifier(FieldGlass(error: error))
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Panel

struct LinkerPanelView: View {
    @ObservedObject var model: PanelModel
    var onHide: () -> Void
    @FocusState private var searchFocused: Bool
    @FocusState private var addFocused: AddFieldKind?
    private var palette: PanelPalette { PanelPalette() }

    var body: some View {
        Group {
            if model.addMode {
                addView
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                listView
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.smooth(duration: 0.18), value: model.addMode)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .modifier(PanelGlass())
        .onReceive(model.$focusToken) { token in
            guard token > 0, !model.addMode else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
        }
        .onReceive(model.$addFocusToken) { token in
            guard token > 0, model.addMode else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { addFocused = .alias }
        }
        .onReceive(model.$toast) { toast in
            guard let toast else { return }
            let hidePanel = model.dismissOnToast
            // Ignore a pending dismissal if the user has reopened the panel.
            let token = model.focusToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                if model.toast == toast && model.focusToken == token && hidePanel { onHide() }
            }
        }
    }

    // MARK: list mode

    private var listView: some View {
        VStack(spacing: 0) {
            header
            searchBar
            tagBar
            listHeading
            results
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "link")
                .font(.system(size: 19, weight: .medium))
            Text("Linker")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            KeyCap(label: "⌘ ⇧ L")
            IconGlassButton(system: "plus", help: "Add a link (⌘N)") { model.openAdd() }
            IconGlassButton(system: "arrow.clockwise", help: "Reload links (⌘R)") { model.reload() }
        }
        .foregroundColor(palette.ink)
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(palette.muted)
            TextField("Search your links…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(palette.ink)
                .focused($searchFocused)
                .accessibilityLabel("Search links by alias, URL, tag or note")
            if !model.query.isEmpty {
                Button { model.query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(palette.muted)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .modifier(FieldGlass(focused: searchFocused))
        .padding(.horizontal, 20)
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagButton("All links", tag: nil)
                ForEach(model.tags, id: \.self) { tag in tagButton(tag, tag: tag) }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private func tagButton(_ title: String, tag: String?) -> some View {
        Button { model.selectedTag = tag } label: {
            Text(title)
                .font(.system(size: 12, weight: model.selectedTag == tag ? .medium : .regular))
                .foregroundColor(model.selectedTag == tag ? palette.ink : palette.muted)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(model.selectedTag == tag ? palette.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.map { "Filter by \($0)" } ?? "Show all links")
        .accessibilityAddTraits(model.selectedTag == tag ? .isSelected : [])
    }

    private var listHeading: some View {
        HStack(spacing: 8) {
            Text(model.query.isEmpty ? (model.selectedTag ?? "Your links") : "Search results")
            Spacer()
            Text("\(model.matches.count) \(model.matches.count == 1 ? "link" : "links")")
                .monospacedDigit()
            Button { model.toggleSort() } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.sortMode == .alpha ? "textformat.abc" : "clock")
                        .font(.system(size: 10, weight: .medium))
                    Text(model.sortMode == .alpha ? "A–Z" : "Recent")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.muted)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(palette.field)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Toggle between A–Z and recently-copied order (⌘S)")
            .accessibilityLabel("Sort order")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(palette.faint)
        .padding(.horizontal, 24)
        .frame(height: 28)
    }

    private var results: some View {
        Group {
            if let error = model.loadError {
                message(symbol: "exclamationmark.triangle", title: "Couldn’t load your links", detail: error) {
                    GlassPill { model.reload() } label: {
                        Text("Try again").font(.system(size: 12, weight: .medium))
                    }
                }
            } else if model.links.isEmpty {
                message(symbol: "link.badge.plus", title: "Your links start here",
                        detail: "Add one right here, or save it in Terminal — both land in the same library.") {
                    VStack(spacing: 10) {
                        GlassPill { model.openAdd() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                Text("Add your first link")
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        Text("linker add github https://github.com")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(palette.field)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if model.matches.isEmpty {
                message(symbol: "magnifyingglass", title: "No links found",
                        detail: "Try another alias, URL, tag or note.") {
                    GlassPill {
                        model.clearFilters(); searchFocused = true
                    } label: {
                        Text("Clear filters").font(.system(size: 12, weight: .medium))
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.matches.enumerated()), id: \.element.id) { idx, link in
                                LinkRow(link: link, selected: idx == model.selected,
                                        copied: model.copiedAlias == link.alias,
                                        showRecency: model.sortMode == .recent && model.query.isEmpty,
                                        onCopy: { model.copy(link) },
                                        onOpen: {
                                            if model.open(link) { onHide() }
                                        },
                                        onEdit: { model.openEdit(link) },
                                        onDelete: { model.delete(link) })
                                    .id(link.id)
                                    .onHover { hovering in
                                        if hovering { model.selected = idx }
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: model.selected) { _ in
                        if let link = model.selectedLink { proxy.scrollTo(link.id) }
                    }
                    .onChange(of: model.query) { _ in
                        if let link = model.selectedLink { proxy.scrollTo(link.id, anchor: .top) }
                    }
                    .onChange(of: model.selectedTag) { _ in
                        if let link = model.selectedLink { proxy.scrollTo(link.id, anchor: .top) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message<Action: View>(symbol: String, title: String, detail: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(palette.muted)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .foregroundColor(palette.ink)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let toast = model.toast {
                let deleting = model.pendingDeleteRecord != nil
                Image(systemName: deleting ? "trash" : "checkmark.circle.fill")
                    .foregroundColor(deleting ? palette.muted : palette.success)
                Text(toast).foregroundColor(palette.ink).lineLimit(1)
                if model.pendingDeleteRecord != nil {
                    GlassPill { model.undoDelete() } label: {
                        Text("Undo").font(.system(size: 11, weight: .medium))
                    }
                    .help("Put the deleted link back (⌘Z)")
                }
                Spacer(minLength: 0)
            } else if let error = model.actionError {
                Text(error).foregroundColor(palette.ink).lineLimit(2)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 4) {
                    KeyCap(label: "↑"); KeyCap(label: "↓")
                    Text("Navigate")
                    Text("·")
                    Text("⌘E edit · ⌘⌫ delete")
                }
                Spacer(minLength: 0)
                GlassPill(action: {
                    if let link = model.selectedLink, model.open(link) { onHide() }
                }, disabled: model.selectedLink == nil) {
                    HStack(spacing: 4) { Text("Open"); KeyCap(label: "⌘ ↵") }
                }
                .help("Open the selected link in your browser")
                GlassPill(action: {
                    if let link = model.selectedLink { model.copy(link) }
                }, disabled: model.selectedLink == nil) {
                    HStack(spacing: 4) { Text("Copy"); KeyCap(label: "↵") }
                        .foregroundColor(palette.ink)
                }
                .help("Copy the selected URL")
            }
        }
        .font(.system(size: 12))
        .foregroundColor(palette.muted)
        .padding(.horizontal, 20)
        .frame(height: 52)
        .modifier(FooterGlass())
    }

    // MARK: add mode

    private var addView: some View {
        VStack(spacing: 0) {
            addHeader
            addForm
            Spacer(minLength: 0)
            addFooter
        }
    }

    private var addHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: model.editingAlias == nil ? "plus.circle" : "pencil.circle")
                .font(.system(size: 19, weight: .medium))
            Text(model.editingAlias == nil ? "Add a link" : "Edit “\(model.editingAlias ?? "")”")
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            KeyCap(label: "esc")
            IconGlassButton(system: "xmark", help: "Cancel (esc)") { model.cancelAdd() }
        }
        .foregroundColor(palette.ink)
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddField(icon: "at", title: "Alias",
                     text: $model.draftAlias, placeholder: "github",
                     field: .alias, focus: $addFocused,
                     onSubmit: { addFocused = .url },
                     error: model.aliasError ?? model.addError)
            AddField(icon: "link", title: "URL",
                     text: $model.draftURL, placeholder: "https://example.com — https:// added if missing",
                     field: .url, focus: $addFocused,
                     onSubmit: { model.submitAdd() },
                     error: model.urlError)
            AddField(icon: "tag", title: "Tags",
                     text: $model.draftTags, placeholder: "dev, identity (comma-separated)",
                     field: .tags, focus: $addFocused,
                     onSubmit: { model.submitAdd() })
            AddField(icon: "note.text", title: "Note",
                     text: $model.draftNote, placeholder: "main profile (optional)",
                     field: .note, focus: $addFocused,
                     onSubmit: { model.submitAdd() })
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var addFooter: some View {
        HStack(spacing: 12) {
            if let error = model.addError {
                Text(error).foregroundColor(palette.ink).lineLimit(2)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 4) {
                    KeyCap(label: "↵")
                    Text("Save")
                }
                Text("·")
                KeyCap(label: "esc")
                Text("Cancel")
                Spacer(minLength: 0)
            }
            GlassPill { model.cancelAdd() } label: {
                Text("Cancel").font(.system(size: 12, weight: .medium))
            }
            GlassPill(action: { model.submitAdd() },
                      disabled: !model.canSubmitAdd) {
                HStack(spacing: 5) {
                    Image(systemName: model.editingAlias == nil ? "checkmark" : "pencil")
                    Text(model.editingAlias == nil ? "Save link" : "Save changes")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.ink)
            }
            .help("Save to links.json")
        }
        .font(.system(size: 12))
        .foregroundColor(palette.muted)
        .padding(.horizontal, 20)
        .frame(height: 52)
        .modifier(FooterGlass())
    }
}
