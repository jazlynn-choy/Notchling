import NotchlingCore
import SwiftUI

/// The to-do list, two-way synced with Apple Reminders.
struct RemindersCard: View {
    @EnvironmentObject var reminders: RemindersStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch reminders.access {
            case .granted: list
            case .notDetermined: connectPrompt
            case .denied: deniedMessage
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist").font(.system(size: 10, weight: .bold)).foregroundStyle(.yellow)
            Text("Reminders").font(.system(size: 11, weight: .bold))
            if reminders.openCount > 0 {
                Text("\(reminders.openCount)").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if let error = reminders.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .help(error)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    @ViewBuilder private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                if reminders.items.isEmpty {
                    Text("All done 🎉").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
                ForEach(reminders.items) { todo in
                    ReminderRow(todo: todo) { reminders.toggle(todo) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)

        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            TextField("Add a reminder", text: $reminders.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit { Task { await reminders.addDraft() } }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
    }

    private var connectPrompt: some View {
        VStack {
            Spacer(minLength: 0)
            Button("Connect to Reminders") { Task { await reminders.requestAccess() } }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.yellow))
                .foregroundStyle(.black)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var deniedMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notchling can't see Reminders. Allow it in System Settings → Privacy & Security → Reminders.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.yellow)
        }
    }
}

struct ReminderRow: View {
    let todo: Todo
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(todo.isDone ? Color.green : Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark \(todo.title) not done" : "Complete \(todo.title)")
            Text(todo.title)
                .font(.system(size: 11))
                .strikethrough(todo.isDone)
                .foregroundStyle(.white.opacity(todo.isDone ? 0.4 : 0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = todo.due {
                let label = DueDateLabel.make(for: due)
                Text(label.text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(label.isOverdue ? Color.red : Color.white.opacity(0.45))
            }
        }
    }
}
