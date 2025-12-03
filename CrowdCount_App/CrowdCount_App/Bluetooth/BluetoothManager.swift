import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    @Published var isBluetoothReady: Bool = false
    @Published var isScanning: Bool = false

    // MARK: - Device Identity (from QR code)
    var deviceId: String = ""
    var deviceSecret: String = ""

    // MARK: - Hardcoded UUIDs for CrowdCount Provisioning
    // These UUIDs are fixed for all CrowdCount devices
    private let serviceUUID = CBUUID(string: "e3e64d66-1db1-11ec-9621-0242ac130002")
    private let authUUID = CBUUID(string: "e3e64d67-1db1-11ec-9621-0242ac130002")
    private let ssidUUID = CBUUID(string: "e3e64f08-1db1-11ec-9621-0242ac130002")
    private let passwordUUID = CBUUID(string: "e3e6515a-1db1-11ec-9621-0242ac130002")
    private let tailscaleKeyUUID = CBUUID(string: "e3e65276-1db1-11ec-9621-0242ac130002")
    private let serverIPUUID = CBUUID(string: "e3e65398-1db1-11ec-9621-0242ac130002")
    private let streamNameUUID = CBUUID(string: "e3e654ba-1db1-11ec-9621-0242ac130002")

    // MARK: - Bluetooth Components
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?

    // Characteristics
    private var authCharacteristic: CBCharacteristic?
    private var ssidCharacteristic: CBCharacteristic?
    private var passwordCharacteristic: CBCharacteristic?
    private var tailscaleKeyCharacteristic: CBCharacteristic?
    private var serverIPCharacteristic: CBCharacteristic?
    private var streamNameCharacteristic: CBCharacteristic?

    // MARK: - State Management
    private var retryCount = 0
    private let maxRetryCount = 3
    private var isAuthenticated = false

    override init() {
        super.init()
        print("BluetoothManager initialized")
    }

    // MARK: - Public Methods

    func initializeCentralManager() {
        print("Initializing CBCentralManager")
        centralManager = CBCentralManager(delegate: self, queue: nil)
        isBluetoothReady = true
        print("CBCentralManager initialized")
    }

    func startScanning() {
        guard !deviceId.isEmpty else {
            print("Error: Device ID not set. Cannot start scanning.")
            connectionError = "Device ID not set"
            return
        }

        print("Starting to scan for peripheral with service UUID: \(serviceUUID)")
        print("Looking for device: CrowdCount-\(deviceId)")
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func stopScanning() {
        print("Stopping scan")
        isScanning = false
        centralManager.stopScan()
    }

    func disconnect() {
        if let peripheral = peripheral {
            print("Disconnecting from peripheral")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Send Provisioning Data

    func sendProvisioningData(
        ssid: String,
        password: String,
        tailscaleKey: String,
        serverIP: String,
        streamName: String? = nil
    ) {
        guard let peripheral = peripheral else {
            connectionError = "Not connected to device"
            print("Error: No peripheral connected")
            return
        }

        guard isAuthenticated else {
            connectionError = "Not authenticated"
            print("Error: Device not authenticated")
            return
        }

        // Send WiFi credentials
        if let ssidChar = ssidCharacteristic,
           let pwdChar = passwordCharacteristic {
            let ssidData = ssid.data(using: .utf8)!
            let passwordData = password.data(using: .utf8)!

            print("Sending WiFi SSID: \(ssid)")
            peripheral.writeValue(ssidData, for: ssidChar, type: .withResponse)

            print("Sending WiFi Password: \(String(repeating: "*", count: password.count))")
            peripheral.writeValue(passwordData, for: pwdChar, type: .withResponse)
        } else {
            connectionError = "WiFi characteristics not found"
            print("Error: WiFi characteristics not available")
            return
        }

        // Send Tailscale key
        if let tailscaleChar = tailscaleKeyCharacteristic {
            let tailscaleData = tailscaleKey.data(using: .utf8)!
            print("Sending Tailscale auth key")
            peripheral.writeValue(tailscaleData, for: tailscaleChar, type: .withResponse)
        } else {
            connectionError = "Tailscale characteristic not found"
            print("Error: Tailscale characteristic not available")
            return
        }

        // Send server IP
        if let serverChar = serverIPCharacteristic {
            let serverData = serverIP.data(using: .utf8)!
            print("Sending server IP: \(serverIP)")
            peripheral.writeValue(serverData, for: serverChar, type: .withResponse)
        } else {
            connectionError = "Server IP characteristic not found"
            print("Error: Server IP characteristic not available")
            return
        }

        // Send stream name (optional)
        if let streamChar = streamNameCharacteristic,
           let stream = streamName, !stream.isEmpty {
            let streamData = stream.data(using: .utf8)!
            print("Sending stream name: \(stream)")
            peripheral.writeValue(streamData, for: streamChar, type: .withResponse)
        }

        print("All provisioning data sent successfully")
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central manager state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            isBluetoothReady = true
        case .poweredOff:
            print("Bluetooth is powered off")
            isBluetoothReady = false
            connectionError = "Please turn on Bluetooth"
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth is unauthorized")
            connectionError = "Bluetooth access denied"
        case .unsupported:
            print("Bluetooth is unsupported")
            connectionError = "Bluetooth not supported on this device"
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Bluetooth state is unknown and not handled")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")

        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("Peripheral local name: \(localName)")

            // Match device name format: "CrowdCount-CC-00001"
            let expectedName = "CrowdCount-\(deviceId)"
            if localName == expectedName {
                print("✓ Matching peripheral found: \(localName)")
                self.peripheral = peripheral
                self.peripheral?.delegate = self
                centralManager.stopScan()
                isScanning = false
                centralManager.connect(peripheral, options: nil)
            } else {
                print("Device name mismatch. Expected: \(expectedName), Got: \(localName)")
            }
        } else {
            print("No local name in advertisement data")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✓ Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnected = true
        retryCount = 0

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        print("Discovering services...")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("✗ Failed to connect to peripheral: \(peripheral.name ?? "Unknown"). Error: \(error?.localizedDescription ?? "None")")

        if retryCount < maxRetryCount {
            retryCount += 1
            print("Retrying connection (\(retryCount)/\(maxRetryCount))")
            centralManager.connect(peripheral, options: nil)
        } else {
            connectionError = "Failed to connect to device after \(maxRetryCount) attempts"
            print("Exceeded maximum retry attempts")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown"). Error: \(error?.localizedDescription ?? "None")")
        isConnected = false
        isAuthenticated = false

        // Clear characteristics
        authCharacteristic = nil
        ssidCharacteristic = nil
        passwordCharacteristic = nil
        tailscaleKeyCharacteristic = nil
        serverIPCharacteristic = nil
        streamNameCharacteristic = nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("✗ Error discovering services: \(error.localizedDescription)")
            connectionError = "Error discovering services"
            return
        }

        guard let services = peripheral.services else {
            print("No services found")
            return
        }

        for service in services {
            print("✓ Discovered service: \(service.uuid)")
            if service.uuid == serviceUUID {
                print("Found provisioning service, discovering characteristics...")
                peripheral.discoverCharacteristics([
                    authUUID,
                    ssidUUID,
                    passwordUUID,
                    tailscaleKeyUUID,
                    serverIPUUID,
                    streamNameUUID
                ], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("✗ Error discovering characteristics: \(error.localizedDescription)")
            connectionError = "Error discovering characteristics"
            return
        }

        guard let characteristics = service.characteristics else {
            print("No characteristics found for service: \(service.uuid)")
            return
        }

        for characteristic in characteristics {
            print("✓ Discovered characteristic: \(characteristic.uuid)")

            switch characteristic.uuid {
            case authUUID:
                authCharacteristic = characteristic
                print("  → Auth characteristic assigned")
                // Automatically authenticate
                authenticateWithDevice()
            case ssidUUID:
                ssidCharacteristic = characteristic
                print("  → SSID characteristic assigned")
            case passwordUUID:
                passwordCharacteristic = characteristic
                print("  → Password characteristic assigned")
            case tailscaleKeyUUID:
                tailscaleKeyCharacteristic = characteristic
                print("  → Tailscale key characteristic assigned")
            case serverIPUUID:
                serverIPCharacteristic = characteristic
                print("  → Server IP characteristic assigned")
            case streamNameUUID:
                streamNameCharacteristic = characteristic
                print("  → Stream name characteristic assigned")
            default:
                print("  → Unknown characteristic")
            }
        }

        // Check if all required characteristics were found
        if authCharacteristic == nil ||
           ssidCharacteristic == nil ||
           passwordCharacteristic == nil ||
           tailscaleKeyCharacteristic == nil ||
           serverIPCharacteristic == nil {
            connectionError = "Required characteristics not found"
            print("✗ Missing required characteristics")
        } else {
            connectionError = nil
            print("✓ All characteristics assigned successfully")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("✗ Error writing to characteristic \(characteristic.uuid): \(error.localizedDescription)")
            connectionError = "Failed to write data"
        } else {
            print("✓ Successfully wrote to characteristic: \(characteristic.uuid)")

            // If this was the auth characteristic, mark as authenticated
            if characteristic.uuid == authUUID {
                isAuthenticated = true
                print("✓ Device authenticated successfully")
            }
        }
    }

    // MARK: - Private Methods

    private func authenticateWithDevice() {
        guard let authChar = authCharacteristic else {
            print("✗ Auth characteristic not available")
            return
        }

        guard !deviceSecret.isEmpty else {
            print("✗ Device secret not set")
            connectionError = "Device secret missing"
            return
        }

        let secretData = deviceSecret.data(using: .utf8)!
        print("Sending device secret for authentication...")
        peripheral?.writeValue(secretData, for: authChar, type: .withResponse)
    }
}
