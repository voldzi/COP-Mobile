import SwiftUI

@main
struct COPMobileApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
    }
  }
}
