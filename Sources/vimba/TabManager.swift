import Foundation
import WebKit

/// Holds the open buffers.
///
/// Buffers are global, as in vim: which one is on screen is a property of a
/// pane, not of this list. Tabs stay live so their state survives switching,
/// but any tab that is not displayed and has been idle past
/// `Config.tabIdleTimeout` is suspended to give its memory back.
@MainActor
final class TabManager {
    private(set) var tabs: [Tab] = []

    var onTabChanged: ((Tab) -> Void)?
    /// Asked before suspending, so a buffer visible in a pane is left alone.
    var isVisible: ((Tab) -> Bool)?

    private let configuration: WKWebViewConfiguration
    private var suspensionTask: Task<Void, Never>?

    /// Buffer names, in open order.
    var displayNames: [String] {
        tabs.map(\.displayName)
    }

    init(configuration: WKWebViewConfiguration) {
        self.configuration = configuration
    }

    deinit {
        suspensionTask?.cancel()
    }

    /// `configuration` is only passed when WebKit hands one over for a
    /// window the page opened: the returned web view has to be built with
    /// exactly that object or WebKit refuses it.
    @discardableResult
    func newTab(configuration override: WKWebViewConfiguration? = nil) -> Tab {
        let tab = Tab(configuration: override ?? configuration)
        tab.onChange = { [weak self] changed in
            self?.onTabChanged?(changed)
        }
        tabs.append(tab)
        return tab
    }

    func tab(named name: String) -> Tab? {
        tabs.first { $0.displayName == name }
    }

    func index(of tab: Tab) -> Int? {
        tabs.firstIndex { $0 === tab }
    }

    /// Returns the buffer `offset` positions along from `tab`, wrapping round.
    func tab(after tab: Tab, offset: Int) -> Tab? {
        guard let index = index(of: tab), !tabs.isEmpty else { return nil }
        let next = (index + offset % tabs.count + tabs.count) % tabs.count
        return tabs[next]
    }

    /// Closing the last buffer is refused: a pane always shows something.
    @discardableResult
    func close(_ tab: Tab) -> Bool {
        guard tabs.count > 1, let index = index(of: tab) else { return false }
        tabs.remove(at: index)
        tab.teardown()
        return true
    }

    func startSuspending() {
        suspensionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.suspendIdleTabs()
            }
        }
    }

    private func suspendIdleTabs() {
        let cutoff = Date().addingTimeInterval(-Config.tabIdleTimeout)
        for tab in tabs where !(isVisible?(tab) ?? false) {
            if tab.lastAccessed < cutoff {
                tab.suspendIfQuiet()
            }
        }
    }
}
