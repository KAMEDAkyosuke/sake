import SakeKit
import SwiftUI

enum WindowID {
    static let library = "library"
    static let setup = "setup"
}

@main
struct SakeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // Not WindowGroups: there is one of each of these, and a "New Sake Window" item in
        // the File menu would offer a second copy of the same state.
        Window("Sake", id: WindowID.library) {
            LibraryWindow().environment(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 420)

        // Not a UtilityWindow either, although docs/layout.md once expected the setup flow
        // to use one: a utility window has `hidesOnDeactivate`, and the D3DMetal step's
        // whole job is to send the user to a browser to fetch Apple's toolkit.
        Window("Setting Up sake", id: WindowID.setup) {
            SetupWindow().environment(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 560)
    }
}
