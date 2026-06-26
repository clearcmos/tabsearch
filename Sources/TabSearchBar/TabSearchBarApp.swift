import SwiftUI

@main
struct TabSearchBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("tabsearch", systemImage: "magnifyingglass") {
            Button("Search all tabs   (Shift+Cmd+F)") {
                delegate.controller.toggle()
            }
            Divider()
            Button("Quit tabsearch") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)  // no Dock icon
        controller.start()
    }
}
