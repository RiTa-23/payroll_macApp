import SwiftUI

@main
struct PayrollApp: App {
    @State private var compact = UserDefaults.standard.bool(forKey: "payroll.compact")

    var body: some Scene {
        WindowGroup("給与計算") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: compact ? 560 : 1020, height: compact ? 420 : 660)
    }
}
