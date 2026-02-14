import SwiftUI

/// Device management list — shows devices in a location with status indicators
struct DeviceManagementListView: View {
    let location: AppLocation
    let devices: [Device]
    let deviceStatuses: [String: String]
    let removeDeviceFromLocation: (String) async -> Void
    let logOut: (String) -> Void

    @State private var deviceToRemove: String? = nil
    @State private var showRemoveConfirmation: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Text("Counters")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    if devices.isEmpty {
                        Text("No counters in this location")
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    } else {
                        ForEach(devices) { device in
                            DeviceManagementRow(
                                device: device,
                                isOffline: deviceStatuses[device.deviceId] != "online",
                                onRemove: {
                                    deviceToRemove = device.deviceId
                                    showRemoveConfirmation = true
                                },
                                logOut: logOut
                            )
                        }
                    }
                }
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Remove Counter?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                deviceToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let deviceId = deviceToRemove {
                    Task {
                        await removeDeviceFromLocation(deviceId)
                    }
                    deviceToRemove = nil
                }
            }
        } message: {
            if let deviceId = deviceToRemove {
                Text("Remove \(NicknameManager.shared.displayName(for: deviceId)) from this location? You will need to re-add it if you want to use it again.")
            }
        }
    }
}

/// A single device row in the management list
struct DeviceManagementRow: View {
    let device: Device
    let isOffline: Bool
    let onRemove: () -> Void
    let logOut: (String) -> Void

    @ObservedObject private var nicknameManager = NicknameManager.shared
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var deviceName: String = ""
    @State private var isEditingName: Bool = false
    @State private var showSettings: Bool = false
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: isOffline ? "wifi.slash" : "wifi")
                    .foregroundColor(isOffline ? .red : .green)
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28)

                // Name and device ID
                VStack(alignment: .leading, spacing: 2) {
                    if isEditingName {
                        HStack {
                            TextField(device.deviceId, text: $deviceName)
                                .font(.headline)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(6)
                            Button("Done") {
                                saveDeviceName()
                                isEditingName = false
                            }
                            .font(.caption.bold())
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(deviceName.isEmpty ? device.deviceId : deviceName)
                                .font(.headline)
                            Button(action: { isEditingName = true }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if deviceName != device.deviceId && !deviceName.isEmpty {
                        Text(device.deviceId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(isOffline ? "Offline" : "Online")
                        .font(.caption)
                        .foregroundColor(isOffline ? .red : .green)

}

                Spacer()

                // Settings button
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.3))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Bluetooth/WiFi setup link when offline
            if isOffline {
                Divider()
                    .padding(.horizontal, 16)

                NavigationLink(destination: CounterPlacementGuideView(
                    wifiSSID: $wifiSSID,
                    wifiPassword: $wifiPassword,
                    bluetoothManager: bluetoothManager,
                    sendWiFiCredentials: {}
                )) {
                    HStack {
                        Image(systemName: "wifi.exclamationmark")
                        Text("Connect to WiFi")
                            .font(.subheadline)
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            deviceName = nicknameManager.nickname(for: device.deviceId)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                showSettings: $showSettings,
                device: device,
                logOut: logOut
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private func saveDeviceName() {
        nicknameManager.setNickname(deviceName, for: device.deviceId)
    }
}
