import SwiftUI

/// View for adding a new device to an existing location
struct AddDeviceToLocationView: View {
    let locationName: String
    let addDeviceToLocation: (String, String, String) async -> Void  // (deviceId, password, label)
    @ObservedObject var alertViewModel: AlertViewModel
    let locationHasDevices: Bool
    var isOnMap: Bool = false
    var onDeleteLocation: (() -> Void)? = nil
    var onOpenLocationList: (() -> Void)? = nil

    @State private var deviceId: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isAdding: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    @EnvironmentObject var appSettings: AppSettings
    @FocusState private var focusedField: Field?

    enum Field {
        case deviceId, password
    }

    var body: some View {
        if isOnMap {
            mapLocationContent
        } else {
            addCounterContent
        }
    }

    // MARK: - Map Location (read-only)

    private var mapLocationContent: some View {
        VStack {
            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "map.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundColor(.green)
                    .padding(.bottom, 8)

                Text("Map Location")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(locationName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 20)

            Text("This location is managed on the CrowdCount map. Its counters are set by the map configuration and can't be changed here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if let onOpenLocationList {
                Button(action: onOpenLocationList) {
                    HStack(spacing: 4) {
                        Text("Add counters to a different location")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 16)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Add Counter Form

    private var addCounterContent: some View {
        VStack {
            Spacer()

            // Header
            VStack(spacing: 4) {
                Image(systemName: "plus.bubble")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                Text(locationHasDevices ? "Add another counter to" : "Add a counter to")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(locationName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 20)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.bottom, 8)
            }

            // Input fields
            VStack(spacing: 10) {
                TextField("Device ID", text: $deviceId, onEditingChanged: { _ in clearErrorMessage() })
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(14)
                    .focused($focusedField, equals: .deviceId)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password, onCommit: clearErrorMessage)
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(14)
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Add button
            Button(action: addDevice) {
                Group {
                    if isAdding {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Text("Add Counter")
                            .fontWeight(.medium)
                    }
                }
                .frame(minWidth: 140)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(Color.blue.opacity(0.75))
                .foregroundColor(.primary)
                .cornerRadius(20)
            }
            .disabled(isAdding)

            // Subtitle + location list link
            VStack(spacing: 6) {
                if !locationHasDevices {
                    Text("Add your first counter to get started.")
                } else if let onOpenLocationList {
                    Button(action: onOpenLocationList) {
                        HStack(spacing: 4) {
                            Text("Or go to a different location")
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 14)

            Spacer()

            // Delete Location button — only for empty locations
            if !locationHasDevices, onDeleteLocation != nil {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete Location")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(20)
                }
                .padding(.bottom, 20)
            }
        }
        .padding()
        .onTapGesture {
            focusedField = nil
        }
        .onDisappear {
            focusedField = nil
            clearFields()
        }
        .alert("Delete Location?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDeleteLocation?()
            }
        } message: {
            Text("Are you sure you want to delete '\(locationName)'? This cannot be undone.")
        }
    }

    private func addDevice() {
        guard !deviceId.isEmpty else {
            errorMessage = "Please enter a Device ID"
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter a Password"
            return
        }

        isAdding = true
        let id = deviceId
        let pw = password

        Task {
            do {
                // Validate credentials first
                let valid = try await APIService.shared.checkPassword(deviceId: id, password: pw)
                if valid {
                    await addDeviceToLocation(id, pw, id)
                    await MainActor.run {
                        clearFields()
                        isAdding = false
                        focusedField = nil
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Incorrect Device ID or Password"
                        isAdding = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection error. Please try again."
                    isAdding = false
                }
            }
        }
    }

    private func clearFields() {
        deviceId = ""
        password = ""
        errorMessage = nil
    }

    private func clearErrorMessage() {
        errorMessage = nil
    }
}
