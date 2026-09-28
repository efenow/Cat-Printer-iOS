import CoreBluetooth
import Foundation

struct ScannedDevice {
    let name: String
    let address: String
}

struct PrinterModel {
    let name: String
    let paperWidth: Int
    let isNewKind: Bool
    let problemFeeding: Bool
}

enum PrinterServiceError: LocalizedError {
    case bluetoothUnavailable
    case scanInProgress
    case connectInProgress
    case noDevice
    case characteristicMissing
    case invalidPBM(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .scanInProgress: return "Scan already in progress"
        case .connectInProgress: return "Connect already in progress"
        case .noDevice: return "No connected printer"
        case .characteristicMissing: return "Printer characteristic missing"
        case let .invalidPBM(message): return message
        }
    }
}

final class BLEPrinterService: NSObject {
    private lazy var central = CBCentralManager(delegate: self, queue: nil)

    private let txUUID = CBUUID(string: "0000AE01-0000-1000-8000-00805F9B34FB")
    private let rxUUID = CBUUID(string: "0000AE02-0000-1000-8000-00805F9B34FB")

    private var discovered: [UUID: CBPeripheral] = [:]
    private var discoveredNames: [UUID: String] = [:]

    private var connected: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var selectedModel = Self.models["_ZZ00"]!

    private var scanContinuation: CheckedContinuation<[ScannedDevice], Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var pendingServiceDiscoveryCount = 0

    private var flowPaused = false

    private static let models: [String: PrinterModel] = {
        let all = ["_ZZ00", "GB01", "GB02", "GB03", "GT01", "MX05", "MX06", "MX08", "MX09", "MX10", "MX11", "PD01", "YT01", "SC03h", "MXTP"]
        var map: [String: PrinterModel] = [:]
        for name in all {
            map[name] = PrinterModel(name: name, paperWidth: 384, isNewKind: false, problemFeeding: ["MX05", "MX06", "MX08", "MX09", "MX10"].contains(name))
        }
        map["GB03"] = PrinterModel(name: "GB03", paperWidth: 384, isNewKind: true, problemFeeding: false)
        return map
    }()

    func scan(scanTime: TimeInterval, everything: Bool) async throws -> [ScannedDevice] {
        guard central.state == .poweredOn else { throw PrinterServiceError.bluetoothUnavailable }
        guard scanContinuation == nil else { throw PrinterServiceError.scanInProgress }

        discovered.removeAll()
        discoveredNames.removeAll()

        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        return try await withCheckedThrowingContinuation { cont in
            scanContinuation = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + scanTime) { [weak self] in
                guard let self else { return }
                self.central.stopScan()

                let devices = self.discovered.compactMap { uuid, peripheral in
                    let name = self.discoveredNames[uuid] ?? peripheral.name ?? "Unknown"
                    if everything || Self.isValidModel(name) {
                        return ScannedDevice(name: name, address: uuid.uuidString)
                    }
                    return nil
                }.sorted { $0.name < $1.name }

                self.scanContinuation?.resume(returning: devices)
                self.scanContinuation = nil
            }
        }
    }

    func connect(name: String, address: String) async throws {
        guard central.state == .poweredOn else { throw PrinterServiceError.bluetoothUnavailable }
        guard connectContinuation == nil else { throw PrinterServiceError.connectInProgress }
        guard let uuid = UUID(uuidString: address), let peripheral = discovered[uuid] else {
            throw PrinterServiceError.noDevice
        }

        selectedModel = Self.resolveModel(name)
        txCharacteristic = nil
        rxCharacteristic = nil
        pendingServiceDiscoveryCount = 0

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connectContinuation = cont
            if connected?.identifier != peripheral.identifier {
                connected = peripheral
                connected?.delegate = self
                central.connect(peripheral, options: nil)
            } else {
                peripheral.delegate = self
                peripheral.discoverServices(nil)
            }
        }
    }

    func printPBM(_ data: Data, settings: [String: Any]) async throws {
        guard let peripheral = connected else { throw PrinterServiceError.noDevice }
        guard let tx = txCharacteristic else { throw PrinterServiceError.characteristicMissing }

        var pbm = try PBMImage.parse(data)
        let flip = (settings["flip"] as? Bool) ?? false
        let flipH = ((settings["flip_h"] as? Bool) ?? false) || flip
        let flipV = ((settings["flip_v"] as? Bool) ?? false) || flip
        pbm.normalize(to: selectedModel.paperWidth, flipHorizontal: flipH, flipVertical: flipV)

        let speed = (settings["quality"] as? Int) ?? (settings["quality"] as? NSNumber)?.intValue ?? 36
        let energy = (settings["energy"] as? Int) ?? (settings["energy"] as? NSNumber)?.intValue ?? 64
        let dryRun = (settings["dry_run"] as? Bool) ?? false

        var commands = [[UInt8]]()
        commands += prepareCommands(speed: speed, energy: energy)

        for row in pbm.rows {
            let bitmap = dryRun ? [UInt8](repeating: 0, count: row.count) : row
            let reversed = bitmap.map { CatPrinterProtocol.reverseBits($0) }
            commands.append(CatPrinterProtocol.makeCommand(0xA2, payload: reversed))
        }

        commands += finishCommands()

        for command in commands {
            while flowPaused {
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            peripheral.writeValue(Data(command), for: tx, type: .withoutResponse)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func prepareCommands(speed: Int, energy: Int) -> [[UInt8]] {
        var output = [[UInt8]]()
        output.append(CatPrinterProtocol.makeCommand(0xA3, payload: CatPrinterProtocol.intBytes(0x00)))
        if selectedModel.isNewKind {
            output.append([0x12, 0x51, 0x78, 0xA3, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        } else {
            output.append([0x51, 0x78, 0xA3, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        }
        output.append(CatPrinterProtocol.makeCommand(0xA4, payload: CatPrinterProtocol.intBytes(50)))
        output.append(CatPrinterProtocol.makeCommand(0xBD, payload: CatPrinterProtocol.intBytes(speed)))
        output.append(CatPrinterProtocol.makeCommand(0xAF, payload: CatPrinterProtocol.intBytes(energy * 0x100, length: 2)))
        output.append(CatPrinterProtocol.makeCommand(0xBE, payload: CatPrinterProtocol.intBytes(1)))
        output.append(CatPrinterProtocol.makeCommand(0xA9, payload: CatPrinterProtocol.intBytes(0x00)))
        output.append(CatPrinterProtocol.makeCommand(0xA6, payload: [0xAA, 0x55, 0x17, 0x38, 0x44, 0x5F, 0x5F, 0x5F, 0x44, 0x38, 0x2C]))
        return output
    }

    private func finishCommands() -> [[UInt8]] {
        var output = [[UInt8]]()
        output.append(CatPrinterProtocol.makeCommand(0xA6, payload: [0xAA, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17]))
        output.append(CatPrinterProtocol.makeCommand(0xBD, payload: CatPrinterProtocol.intBytes(8)))

        if selectedModel.problemFeeding {
            let empty = [UInt8](repeating: 0, count: selectedModel.paperWidth / 8)
            for _ in 0..<128 {
                output.append(CatPrinterProtocol.makeCommand(0xA2, payload: empty.map { CatPrinterProtocol.reverseBits($0) }))
            }
        } else {
            output.append(CatPrinterProtocol.makeCommand(0xA1, payload: CatPrinterProtocol.intBytes(128, length: 2)))
        }

        output.append(CatPrinterProtocol.makeCommand(0xA3, payload: CatPrinterProtocol.intBytes(0x00)))
        return output
    }

    private static func isValidModel(_ name: String) -> Bool {
        models.keys.contains { name.hasPrefix($0) }
    }

    private static func resolveModel(_ name: String) -> PrinterModel {
        let match = models.keys
            .filter { name.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        return models[match ?? "_ZZ00"] ?? models["_ZZ00"]!
    }
}

extension BLEPrinterService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            scanContinuation?.resume(throwing: PrinterServiceError.bluetoothUnavailable)
            scanContinuation = nil
            connectContinuation?.resume(throwing: PrinterServiceError.bluetoothUnavailable)
            connectContinuation = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discovered[peripheral.identifier] = peripheral
        discoveredNames[peripheral.identifier] = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: error ?? PrinterServiceError.noDevice)
        connectContinuation = nil
    }
}

extension BLEPrinterService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }
        let services = peripheral.services ?? []
        pendingServiceDiscoveryCount = services.count
        if pendingServiceDiscoveryCount == 0 {
            connectContinuation?.resume(throwing: PrinterServiceError.characteristicMissing)
            connectContinuation = nil
            return
        }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == txUUID {
                txCharacteristic = characteristic
            }
            if characteristic.uuid == rxUUID {
                rxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        pendingServiceDiscoveryCount = max(0, pendingServiceDiscoveryCount - 1)
        if txCharacteristic != nil {
            connectContinuation?.resume(returning: ())
            connectContinuation = nil
            return
        }
        if pendingServiceDiscoveryCount == 0 {
            connectContinuation?.resume(throwing: PrinterServiceError.characteristicMissing)
            connectContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        if bytes == CatPrinterProtocol.dataFlowPause {
            flowPaused = true
        } else if bytes == CatPrinterProtocol.dataFlowResume {
            flowPaused = false
        }
    }
}
