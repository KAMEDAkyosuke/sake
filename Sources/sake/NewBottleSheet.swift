import SakeKit
import SwiftUI

/// Naming a bottle and making it, on top of the library.
///
/// The progress row is the wizard's, deliberately: making the second bottle is the same
/// wineboot as making the first, and showing it differently would suggest otherwise.
struct NewBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("New Bottle")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $model.typedBottleName)
                .textFieldStyle(.roundedBorder)
                .disabled(model.creating.isRunning)
                .onSubmit { if problem == nil { create() } }

            Text(problem ?? """
                A Windows environment of its own: its own C: drive, its own registry, its \
                own installed games. An empty one is about a gigabyte.
                """)
                .font(.callout)
                .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            if let name = started {
                Divider()
                BottleView(name: name, status: model.bottleStatus[name])
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if model.creating.isRunning {
                    Button("Stop") { model.creating.stop() }
                } else {
                    Button("Create", action: create)
                        .keyboardShortcut(.defaultAction)
                        .disabled(problem != nil)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// The bottle this sheet has started making, which stays on screen after the field is
    /// typed into again.
    @State private var started: String?

    private var problem: String? {
        Bottle.problem(withName: model.typedBottleName, in: model.paths)
    }

    private func create() {
        let name = Bottle.proposedName(from: model.typedBottleName)
        started = name
        model.create(name)
    }
}
