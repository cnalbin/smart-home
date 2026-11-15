import SwiftUI

@main
struct SmartHomeApp: App {
    @StateObject private var store = SensorStore()
    var body: some Scene {
        WindowGroup {
            Group { if store.isConfigured { MainView() } else { LoginView() } }
                .environmentObject(store).preferredColorScheme(.light)
        }
    }
}
