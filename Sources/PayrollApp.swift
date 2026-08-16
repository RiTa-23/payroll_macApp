import SwiftUI

@main
struct PayrollApp: App {
    var body: some Scene {
        WindowGroup("給与計算") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
