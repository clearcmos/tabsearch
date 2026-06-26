import SwiftUI
import TabSearchKit

/// Backs the search panel. Takes one snapshot of every tab when the panel opens, then
/// filters that snapshot in memory on each keystroke. All published state is mutated on
/// the main thread; only the AppleScript calls run on the background queue.
final class SearchModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [SearchMatch] = []
    @Published var selection: Int = 0
    @Published private(set) var status: String = ""
    /// Bumped each time the panel opens so the view re-asserts text-field focus (onAppear
    /// only fires once because the panel/view is reused across opens).
    @Published private(set) var focusNonce: Int = 0

    /// Set by the panel controller so the model can dismiss the panel after a jump.
    var onRequestClose: (() -> Void)?

    private var snapshots: [TabSnapshot] = []
    private let work = DispatchQueue(label: "com.clearcmos.tabsearch.snapshot")

    func reset() {
        query = ""
        results = []
        selection = 0
        snapshots = []
        status = "Reading tabs..."
    }

    /// Ask the view to (re)focus the search field. Call this once the panel window is key.
    func requestFocus() {
        focusNonce += 1
    }

    func loadSnapshot() {
        work.async { [weak self] in
            let snaps = (try? TerminalBridge.snapshotAllTabs()) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshots = snaps
                self.recompute()
            }
        }
    }

    func onQueryChange() {
        recompute()
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func activateSelection() {
        guard results.indices.contains(selection) else { return }
        let match = results[selection]
        let term = query
        onRequestClose?()  // dismiss first for a snappy feel; the jump then raises Terminal
        work.async {
            try? TerminalBridge.jump(to: match.tab, term: term)
        }
    }

    private func recompute() {
        results = TerminalBridge.filter(snapshots, term: query)
        if results.isEmpty {
            selection = 0
        } else if selection >= results.count {
            selection = results.count - 1
        }

        if query.isEmpty {
            let searchable = snapshots.filter { !$0.history.isEmpty }.count
            status = snapshots.isEmpty
                ? "No Terminal tabs open"
                : "\(snapshots.count) tab(s), \(searchable) with searchable scrollback"
        } else {
            status = results.isEmpty ? "No matches for \"\(query)\"" : "\(results.count) match(es)"
        }
    }
}
