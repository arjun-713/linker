// Native presentation. Layout and colours are mirrored by preview/preview.css.
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 440
    static let height: CGFloat = 568
}

private struct PanelPalette {
    let dark: Bool
    private func grey(_ value: Double) -> Color { Color(white: value / 255) }
    var surface: Color { grey(dark ? 17 : 255) }
    var field: Color { grey(dark ? 27 : 246) }
    var selected: Color { grey(dark ? 42 : 237) }
    var line: Color { grey(dark ? 46 : 230) }
    var control: Color { grey(dark ? 68 : 206) }
    var ink: Color { grey(dark ? 247 : 24) }
    var muted: Color { grey(dark ? 180 : 96) }
    var faint: Color { grey(dark ? 157 : 106) }
    var success: Color { dark ? Color(red: 0.51, green: 0.80, blue: 0.66)
                            : Color(red: 0.15, green: 0.43, blue: 0.29) }
}

private struct KeyCap: View {
    let label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PanelPalette(dark: scheme == .dark)
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
    let onCopy: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PanelPalette(dark: scheme == .dark)
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
        .accessibilityLabel("Copy \(link.alias)")
        .accessibilityValue(link.url)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LinkerPanelView: View {
    @ObservedObject var model: PanelModel
    var onHide: () -> Void
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var palette: PanelPalette { PanelPalette(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            tagBar
            listHeading
            results
            footer
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
        .onReceive(model.$focusToken) { token in
            guard token > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
        }
        .onReceive(model.$toast) { toast in
            guard let toast else { return }
            // Ignore a pending dismissal if the user has reopened the panel.
            let token = model.focusToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                if model.toast == toast && model.focusToken == token { onHide() }
            }
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
            Button { model.reload() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reload links (⌘R)")
            .accessibilityLabel("Reload links")
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
        .background(palette.field)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(searchFocused ? palette.control : palette.line, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
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
        HStack {
            Text(model.query.isEmpty ? (model.selectedTag ?? "Your links") : "Search results")
            Spacer()
            Text("\(model.matches.count) \(model.matches.count == 1 ? "link" : "links")")
                .monospacedDigit()
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
                    Button("Try again") { model.reload() }
                }
            } else if model.links.isEmpty {
                message(symbol: "link.badge.plus", title: "Your links start here",
                        detail: "Save a link in Terminal. It’ll be here when you need it.") {
                    Text("linker add github https://github.com")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .background(palette.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else if model.matches.isEmpty {
                message(symbol: "magnifyingglass", title: "No links found",
                        detail: "Try another alias, URL, tag or note.") {
                    Button("Clear filters") { model.clearFilters(); searchFocused = true }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.matches.enumerated()), id: \.element.id) { idx, link in
                                LinkRow(link: link, selected: idx == model.selected,
                                        copied: model.copiedAlias == link.alias) { model.copy(link) }
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
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
        }
        .foregroundColor(palette.ink)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let toast = model.toast {
                Image(systemName: "checkmark.circle.fill").foregroundColor(palette.success)
                Text(toast).foregroundColor(palette.ink).lineLimit(1)
                Spacer(minLength: 0)
            } else if let error = model.actionError {
                Text(error).foregroundColor(palette.ink).lineLimit(2)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 4) {
                    KeyCap(label: "↑"); KeyCap(label: "↓")
                    Text("Navigate")
                }
                Spacer(minLength: 0)
                Button { if let link = model.selectedLink, model.open(link) { onHide() } } label: {
                    HStack(spacing: 4) { Text("Open"); KeyCap(label: "⌘ ↵") }
                }
                .buttonStyle(.plain)
                .disabled(model.selectedLink == nil)
                .help("Open the selected link in your browser")
                Button { if let link = model.selectedLink { model.copy(link) } } label: {
                    HStack(spacing: 4) { Text("Copy"); KeyCap(label: "↵") }
                        .foregroundColor(palette.ink)
                }
                .buttonStyle(.plain)
                .disabled(model.selectedLink == nil)
                .help("Copy the selected URL")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(palette.muted)
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(palette.field)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
    }
}
