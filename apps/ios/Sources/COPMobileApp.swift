import SwiftUI

@main
struct COPMobileApp: App {
  @UIApplicationDelegateAdaptor(COPMobileAppDelegate.self) private var appDelegate
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
    }
  }
}
