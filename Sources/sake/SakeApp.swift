import SwiftUI

@main
struct SakeApp: App {
    var body: some Scene {
        // Not a WindowGroup: there is one of this window, and a "New Sake Window" item in
        // the File menu would offer a second copy of the same state. Not a UtilityWindow
        // either -- see docs/layout.md.
        Window("Sake", id: "main") {
            SetupView()
        }
        .windowResizability(.contentMinSize)
        // A flexible frame otherwise opens at SwiftUI's own 900x450, which is wider than
        // the text wants to be.
        .defaultSize(width: 560, height: 460)
    }
}
