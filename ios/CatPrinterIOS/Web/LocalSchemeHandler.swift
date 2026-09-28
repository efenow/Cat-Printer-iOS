import Foundation
import WebKit

final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let api: APIService
    private let bundle = Bundle.main

    init(api: APIService) {
        self.api = api
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            fail(task: urlSchemeTask, status: 400, error: "Invalid URL")
            return
        }

        let path = normalizePath(requestURL.path)

        Task {
            do {
                let method = urlSchemeTask.request.httpMethod?.uppercased() ?? "GET"
                if method == "POST", let response = try await api.handle(path: path, body: urlSchemeTask.request.httpBody ?? Data()) {
                    respond(task: urlSchemeTask, data: response, mimeType: "application/json", status: 200)
                    return
                }

                if method == "GET", path == "~every.js" {
                    let data = try loadEveryScript()
                    respond(task: urlSchemeTask, data: data, mimeType: "text/javascript;charset=utf-8", status: 200)
                    return
                }

                if method == "GET" {
                    let data = try loadStatic(path: path.isEmpty ? "index.html" : path)
                    respond(task: urlSchemeTask, data: data, mimeType: mimeType(for: path), status: 200)
                    return
                }

                fail(task: urlSchemeTask, status: 405, error: "Method not allowed")
            } catch let apiError as APIError {
                let body = apiError.json
                respond(task: urlSchemeTask, data: body, mimeType: "application/json", status: 500)
            } catch {
                fail(task: urlSchemeTask, status: 500, error: error.localizedDescription)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.contains("..") else { return "" }
        return trimmed
    }

    private func loadStatic(path: String) throws -> Data {
        guard let base = bundle.resourceURL?.appendingPathComponent("www") else {
            throw LocalError.notFound
        }
        let fileURL = base.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LocalError.notFound
        }
        return try Data(contentsOf: fileURL)
    }

    private func loadEveryScript() throws -> Data {
        let listData = try loadStatic(path: "all-scripts.txt")
        let list = String(decoding: listData, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        var result = Data()
        for script in list {
            result.append(Data("\n// \(script)\n".utf8))
            result.append(try loadStatic(path: script))
        }
        return result
    }

    private func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html;charset=utf-8"
        case "css": return "text/css;charset=utf-8"
        case "js": return "text/javascript;charset=utf-8"
        case "txt": return "text/plain;charset=utf-8"
        case "json": return "application/json;charset=utf-8"
        case "png": return "image/png"
        case "svg": return "image/svg+xml;charset=utf-8"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }

    private func respond(task: WKURLSchemeTask, data: Data, mimeType: String, status: Int) {
        guard let requestURL = task.request.url,
              let response = HTTPURLResponse(url: requestURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mimeType])
        else {
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(task: WKURLSchemeTask, status: Int, error: String) {
        guard let requestURL = task.request.url,
              let response = HTTPURLResponse(url: requestURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else {
            return
        }
        let body = Data("{\"name\":\"Error\",\"details\":\"\(error.replacingOccurrences(of: "\"", with: "'"))\"}".utf8)
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private enum LocalError: Error {
        case notFound
    }
}
