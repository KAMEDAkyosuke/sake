import SakeKit
import SwiftUI

/// Giving a bottle another name.
///
/// No progress row, unlike the sheet that makes one: a rename is a directory rename and is
/// over before the sheet could draw anything.
struct RenameBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Rename “\(bottle.name)”")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $model.typedRenameName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRename { rename() } }

            Text(problem ?? """
                The games in it and everything it remembers about them stay as they are. \
                The name is the folder's, and nothing inside the bottle names it.
                """)
                .font(.callout)
                .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var problem: String? {
        Bottle.problem(withName: model.typedRenameName, in: model.paths, renaming: bottle.name)
    }

    private var canRename: Bool {
        problem == nil && Bottle.proposedName(from: model.typedRenameName) != bottle.name
    }

    private func rename() {
        model.renameBottle(bottle, to: model.typedRenameName)
        dismiss()
    }
}
