import SwiftUI

@main
struct GasworksApp: App {
    @State private var model = GasworksModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

#Preview("iPhone") {
    RootView(model: GasworksModel())
}
