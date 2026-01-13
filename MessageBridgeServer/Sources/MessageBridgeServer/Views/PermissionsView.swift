import SwiftUI
import MessageBridgeCore

/// A window that shows the status of all required permissions
struct PermissionsView: View {
    @Binding var isPresented: Bool
    @State private var permissions: [PermissionStatus] = []
    @State private var isLoading = true

    private let permissionsManager = PermissionsManager.shared

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Permissions Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("MessageBridge Server needs the following permissions to function properly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            Divider()

            if isLoading {
                ProgressView("Checking permissions...")
                    .padding()
            } else {
                // Permissions list
                VStack(spacing: 12) {
                    ForEach(permissions) { permission in
                        PermissionRow(permission: permission, onOpenSettings: {
                            permissionsManager.openSettings(url: permission.settingsURL)
                        })
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Footer with action buttons
            HStack {
                Button("Refresh") {
                    Task {
                        await checkPermissions(showLoading: true)
                    }
                }

                Spacer()

                if allGranted {
                    Button("Continue") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue Anyway") {
                        isPresented = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .task {
            await checkPermissions(showLoading: true)
            // Poll for permission changes every 2 seconds while window is open
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    await checkPermissions(showLoading: false)
                }
            }
        }
    }

    private var allGranted: Bool {
        permissions.allSatisfy { $0.isGranted }
    }

    private func checkPermissions(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        permissions = await permissionsManager.checkAllPermissions()
        if showLoading {
            isLoading = false
        }
    }
}

struct PermissionRow: View {
    let permission: PermissionStatus
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(permission.isGranted ? .green : .red)

            // Permission info
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.name)
                    .font(.headline)

                Text(permission.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Show manual setup note if required and not granted
                if permission.requiresManualSetup && !permission.isGranted {
                    Text("⚠️ Must be added manually via + button in Settings")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Open Settings button (only if not granted)
            if !permission.isGranted {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(permission.isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

#Preview {
    PermissionsView(isPresented: .constant(true))
}
