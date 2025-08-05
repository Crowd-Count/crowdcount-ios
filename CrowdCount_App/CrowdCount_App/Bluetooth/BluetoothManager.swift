import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var ssidCharacteristic: CBCharacteristic?
    private var passwordCharacteristic: CBCharacteristic?
    @Published var userId: String = "" {
        didSet {
            if !userId.isEmpty {
                initializeCentralManager()
            }
        }
    }
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    @Published var isBluetoothReady: Bool = false

    public let serverURL = "https://crowdcount.tech"

    var mainUUID: CBUUID?
    var ssidCharacteristicUUID: CBUUID?
    var passwordCharacteristicUUID: CBUUID?

    private var retryCount = 0
    private let maxRetryCount = 3

    override init() {
        super.init()
        print("BluetoothManager initialized without central manager")
    }

    func initializeCentralManager() {
        print("Initializing CBCentralManager")
        centralManager = CBCentralManager(delegate: self, queue: nil)
        print("CBCentralManager initialized")
    }

    func fetchBluetoothUUIDs(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var fetchSuccess = true
        
        group.enter()
        getBluetoothUUID(idNeeded: "main") { result in
            switch result {
            case .success(let uuid):
                DispatchQueue.main.async {
                    self.mainUUID = CBUUID(string: uuid)
                    print("Main UUID fetched and set: \(uuid)")
                }
            case .failure(let error):
                print("Failed to fetch main UUID: \(error)")
                fetchSuccess = false
            }
            group.leave()
        }
        
        group.enter()
        getBluetoothUUID(idNeeded: "ssid") { result in
            switch result {
            case .success(let uuid):
                DispatchQueue.main.async {
                    self.ssidCharacteristicUUID = CBUUID(string: uuid)
                    print("SSID Characteristic UUID fetched and set: \(uuid)")
                }
            case .failure(let error):
                print("Failed to fetch SSID UUID: \(error)")
                fetchSuccess = false
            }
            group.leave()
        }
        
        group.enter()
        getBluetoothUUID(idNeeded: "password") { result in
            switch result {
            case .success(let uuid):
                DispatchQueue.main.async {
                    self.passwordCharacteristicUUID = CBUUID(string: uuid)
                    print("Password Characteristic UUID fetched and set: \(uuid)")
                }
            case .failure(let error):
                print("Failed to fetch password UUID: \(error)")
                fetchSuccess = false
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.isBluetoothReady = fetchSuccess
            print("UUID fetching completed with success: \(fetchSuccess)")
            completion(fetchSuccess)
        }
    }

    func getBluetoothUUID(idNeeded: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(serverURL)/api/get_bluetooth_id?user_id=\(userId)&id_needed=\(idNeeded)") else {
            completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let bluetoothId = json["bluetooth_id"] as? String {
                    completion(.success(bluetoothId))
                } else {
                    completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid data"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central manager state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on. Starting scan for peripherals.")
            startScanning()
        case .poweredOff:
            print("Bluetooth is powered off.")
        case .resetting:
            print("Bluetooth is resetting.")
        case .unauthorized:
            print("Bluetooth is unauthorized.")
        case .unsupported:
            print("Bluetooth is unsupported.")
        case .unknown:
            print("Bluetooth state is unknown.")
        @unknown default:
            print("Bluetooth state is unknown and not handled.")
        }
    }

    func startScanning() {
        fetchBluetoothUUIDs { success in
            if success, let mainUUID = self.mainUUID {
                print("Starting to scan for peripherals with UUID: \(mainUUID)")
                self.centralManager.scanForPeripherals(withServices: [mainUUID], options: nil)
            } else {
                print("Failed to fetch UUIDs or UUIDs not set.")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("Peripheral local name: \(localName)")
        }
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, localName.contains("CrowdCount: \(userId)") {
            print("Matching peripheral found with name: \(localName)")
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        } else {
            print("No matching peripheral with name: \(advertisementData[CBAdvertisementDataLocalNameKey] ?? "Unknown")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnected = true
        retryCount = 0
        DispatchQueue.main.async {
            self.objectWillChange.send()  // Notify SwiftUI about the state change
        }
        if let mainUUID = mainUUID {
            print("Discovering services for peripheral")
            peripheral.discoverServices([mainUUID])
        } else {
            print("Main UUID not set")
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(peripheral.name ?? "Unknown"). Error: \(error?.localizedDescription ?? "None")")
        if retryCount < maxRetryCount {
            retryCount += 1
            print("Retrying connection (\(retryCount)/\(maxRetryCount))")
            centralManager.connect(peripheral, options: nil)
        } else {
            connectionError = "Failed to connect to peripheral"
            print("Exceeded maximum retry attempts")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown"). Error: \(error?.localizedDescription ?? "None")")
        isConnected = false
        if retryCount < maxRetryCount {
            retryCount += 1
            print("Retrying connection (\(retryCount)/\(maxRetryCount))")
            centralManager.connect(peripheral, options: nil)
        } else {
            connectionError = "Disconnected from peripheral"
            print("Exceeded maximum retry attempts")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            connectionError = "Error discovering services"
            return
        }
        guard let services = peripheral.services else {
            print("No services found")
            return
        }
        for service in services {
            print("Discovered service: \(service.uuid)")
            if let ssidCharacteristicUUID = ssidCharacteristicUUID, let passwordCharacteristicUUID = passwordCharacteristicUUID {
                print("Discovering characteristics for service: \(service.uuid)")
                peripheral.discoverCharacteristics([ssidCharacteristicUUID, passwordCharacteristicUUID], for: service)
            } else {
                print("Characteristic UUIDs not set")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            connectionError = "Error discovering characteristics"
            return
        }
        guard let characteristics = service.characteristics else {
            print("No characteristics found for service: \(service.uuid)")
            return
        }
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == ssidCharacteristicUUID {
                ssidCharacteristic = characteristic
            } else if characteristic.uuid == passwordCharacteristicUUID {
                passwordCharacteristic = characteristic
            }
        }

        if ssidCharacteristic == nil || passwordCharacteristic == nil {
            connectionError = "Required characteristics not found"
            print("Required characteristics not found")
        } else {
            connectionError = nil
            print("Characteristics assigned successfully")
        }
    }

    func sendWiFiCredentials(ssid: String, password: String) {
        guard let peripheral = peripheral,
              let ssidChar = ssidCharacteristic,
              let pwdChar = passwordCharacteristic else {
            connectionError = "Peripheral or characteristics not ready"
            print("Peripheral or characteristics not ready")
            return
        }

        let ssidData = ssid.data(using: .utf8)!
        let passwordData = password.data(using: .utf8)!

        print("Sending SSID: \(ssid)")
        print("Sending Password: \(password)")
        
        peripheral.writeValue(ssidData, for: ssidChar, type: .withResponse)
        peripheral.writeValue(passwordData, for: pwdChar, type: .withResponse)

        print("WiFi credentials sent")
    }
}
