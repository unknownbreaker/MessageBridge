import SwiftUI
import MessageBridgeClientCore

/// A popover view showing contact details (phone number, service, etc.)
struct ContactDetailsView: View {
    let handles: [Handle]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Contact Details")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // List of participants
            ForEach(handles, id: \.id) { handle in
                ContactDetailRow(handle: handle)
            }

            Spacer()
        }
        .padding()
        .frame(width: 300, height: min(CGFloat(handles.count) * 80 + 100, 400))
    }
}

struct ContactDetailRow: View {
    let handle: Handle
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Contact name (if available)
            if let contactName = handle.contactName {
                Text(contactName)
                    .font(.headline)
            }

            // Phone number / email with copy button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(handle.address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Text(handle.service)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    copyToClipboard(handle.address)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
        .padding(.vertical, 4)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isCopied = true

        // Reset the checkmark after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
}

#Preview {
    ContactDetailsView(handles: [
        Handle(
            id: 1,
            address: "+1 (555) 123-4567",
            service: "iMessage",
            contactName: "John Doe"
        ),
        Handle(
            id: 2,
            address: "jane@example.com",
            service: "iMessage",
            contactName: "Jane Smith"
        )
    ])
}
