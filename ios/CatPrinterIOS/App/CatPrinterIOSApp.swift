import SwiftUI

@main
struct CatPrinterIOSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppWebView(model: model)
                .ignoresSafeArea()
        }
    }
}

final class AppModel: ObservableObject {
    let settings = AppSettings()
    let printer = BLEPrinterService()
    lazy var apiService = APIService(settings: settings, printer: printer)
}
