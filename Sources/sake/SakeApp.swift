import SwiftUI

@main
struct SakeApp: App {
    var body: some Scene {
        WindowGroup {
            PreflightView()
        }
        .windowResizability(.contentSize)
    }
}
