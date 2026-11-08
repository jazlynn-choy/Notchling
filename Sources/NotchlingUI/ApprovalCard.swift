import NotchlingCore
import SwiftUI

/// Claude Code is asking permission: show what it wants to do, with Allow / Deny.
/// Takes over the panel until answered (or until Claude Code falls back to the terminal).
struct ApprovalCard: View {
    let now: Date
    @EnvironmentObject var approvals: ApprovalStore

    var body: some View {
        if let request = approvals.requests.first {
            let secondsLeft = approvals.secondsLeft(for: request, now: now)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    Text("Claude wants to \(request.title.prefix(1).lowercased() + request.title.dropFirst())")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(request.project).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }

                if let detail = request.detail {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    decisionButton("Allow", systemImage: "checkmark", color: .green) {
                        approvals.answer(request, .allow)
                    }
                    decisionButton("Deny", systemImage: "xmark", color: .red) {
                        approvals.answer(request, .deny)
                    }
                    Button("Ask in terminal") { approvals.answer(request, .ask) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if approvals.requests.count > 1 {
                        Text("+\(approvals.requests.count - 1) more")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                    }
                    Text("\(secondsLeft)s")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                        .help("Then Claude Code asks in the terminal instead")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Claude Code permission request in \(request.project)")
        }
    }

    private func decisionButton(_ title: String, systemImage: String, color: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(color))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }
}
