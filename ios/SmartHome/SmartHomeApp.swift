import SwiftUI

@main
struct SmartHomeApp: App {
    @StateObject private var store = SensorStore()
    var body: some Scene {
        WindowGroup { MainView().environmentObject(store).preferredColorScheme(.light) }
    }
}
