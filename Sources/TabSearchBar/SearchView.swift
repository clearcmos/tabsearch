import SwiftUI
import TabSearchKit

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))
                TextField("Search all Terminal tabs", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onChange(of: model.query) { _ in model.onQueryChange() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            if model.results.isEmpty {
                VStack {
                    Spacer()
                    Text(model.status).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.offset) { idx, match in
                                ResultRow(match: match, query: model.query, selected: idx == model.selection)
                                    .id(idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selection = idx
                                        model.activateSelection()
                                    }
                            }
                        }
                    }
                    .onChange(of: model.selection) { sel in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(sel, anchor: .center) }
                    }
                }
            }

            Divider()

            HStack {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Up/Down: navigate    Return: jump    Esc: close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: 680, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { focused = true }
        .onChange(of: model.focusNonce) { _ in
            // The controller bumps this only after the window is key, so set focus directly.
            focused = true
        }
    }
}

struct ResultRow: View {
    let match: SearchMatch
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("w\(match.tab.windowIndex) t\(match.tab.tabIndex)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(highlighted(match.line))
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    /// Bolds and tints the first case-insensitive occurrence of the query within the line.
    private func highlighted(_ line: String) -> AttributedString {
        guard !query.isEmpty,
              let range = line.range(of: query, options: .caseInsensitive) else {
            return AttributedString(line)
        }
        var result = AttributedString(String(line[..<range.lowerBound]))
        var hit = AttributedString(String(line[range]))
        hit.foregroundColor = .accentColor
        hit.font = .system(size: 13, weight: .bold, design: .monospaced)
        result.append(hit)
        result.append(AttributedString(String(line[range.upperBound...])))
        return result
    }
}
