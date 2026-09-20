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
        .commands { UninstallCommand(model: model) }

        // Not a UtilityWindow either, although docs/layout.md once expected the setup flow
        // to use one: a utility window has `hidesOnDeactivate`, and the D3DMetal step's
        // whole job is to send the user to a browser to fetch Apple's toolkit.
        Window("Setting Up sake", id: WindowID.setup) {
            SetupWindow().environment(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 560)
        // Both of these are macOS 15.0+, which is this app's deployment floor, so neither
        // needs an availability guard. Without the first, the scene is presented at launch
        // whatever the state of setup is, and the wizard comes up with nothing to do.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Uninstalling is an explicit action in the app rather than something that follows from
/// dragging the bundle away, so it has to live somewhere -- and the app menu is where a Mac
/// app keeps the item that is about the app rather than about what is in the window. See
/// docs/layout.md.
struct UninstallCommand: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Uninstall sake…") {
                // The library can be closed, and a sheet needs a window to sit on.
                openWindow(id: WindowID.library)
                model.isUninstalling = true
            }
        }
    }
}
