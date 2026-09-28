import Foundation

enum APIError: Error {
    case badRequest(String)
    case backend(String, String)

    var json: Data {
        let payload: [String: String]
        switch self {
        case let .badRequest(message):
            payload = ["name": "BadRequest", "details": message]
        case let .backend(name, details):
            payload = ["name": name, "details": details]
        }
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
    }
}

final class APIService {
    private let settings: AppSettings
    private let printer: BLEPrinterService

    init(settings: AppSettings, printer: BLEPrinterService) {
        self.settings = settings
        self.printer = printer
    }

    func handle(path: String, body: Data) async throws -> Data? {
        switch path {
        case "query":
            return try settings.asJSONData()
        case "set":
            let payload = try decodeJSONMap(body)
            settings.update(with: payload)
            return Data("{}".utf8)
        case "devices":
            let payload = try decodeJSONMap(body)
            let everything = (payload["everything"] as? Bool) ?? false
            let scanTime = (settings.values["scan_time"] as? Double) ?? 1.0
            do {
                let devices = try await printer.scan(scanTime: scanTime, everything: everything)
                let response = ["devices": devices.map { ["name": $0.name, "address": $0.address] }]
                return try JSONSerialization.data(withJSONObject: response, options: [])
            } catch {
                throw APIError.backend("BleakError", error.localizedDescription)
            }
        case "connect":
            let payload = try decodeJSONMap(body)
            guard let device = payload["device"] as? String else {
                throw APIError.badRequest("Missing device")
            }
            let parts = device.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw APIError.badRequest("Invalid device")
            }
            do {
                try await printer.connect(name: parts[0], address: parts[1])
                return Data("{}".utf8)
            } catch {
                throw APIError.backend("BleakError", error.localizedDescription)
            }
        case "print":
            do {
                try await printer.printPBM(body, settings: settings.values)
                return Data("{}".utf8)
            } catch let error as PrinterServiceError {
                throw APIError.backend("PrinterError", error.localizedDescription)
            } catch {
                throw APIError.backend("Exception", error.localizedDescription)
            }
        case "exit":
            return Data("{}".utf8)
        default:
            return nil
        }
    }

    private func decodeJSONMap(_ body: Data) throws -> [String: Any] {
        guard !body.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any] else {
            throw APIError.badRequest("Invalid JSON")
        }
        return object
    }
}
