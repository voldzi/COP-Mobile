import CSMCommunicationKit
import SwiftUI

struct RootView: View {
  let model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    switch model.configuration {
    case .success(let configuration):
      ZStack {
        if !model.isUITesting {
          WebHostView(configuration: configuration, model: model)
        }

        switch model.phase {
        case .loading:
          LoadingView(environment: configuration.environment) {
            model.openNativeChat(expectedSubjectID: model.nativeChatExpectedSubjectID)
          }
        case .webContent:
          EmptyView()
        case .offlineFallback(let code):
          TechnicalFallbackView(
            title: "Mapa se nenačetla",
            message:
              "Zkuste mapu načíst znovu nebo otevřete komunikaci. Dříve uložené zprávy mohou být dostupné i bez připojení.",
            diagnosticCode: code,
            retry: model.retry,
            openChat: {
              model.openNativeChat(expectedSubjectID: model.nativeChatExpectedSubjectID)
            }
          )
        case .blocked(let code):
          TechnicalFallbackView(
            title: "Načtení bylo zablokováno",
            message:
              "Origin nebo verze Device API neprošla bezpečnostní kontrolou. Nativní funkce zůstávají vypnuté.",
            diagnosticCode: code,
            retry: model.retry
          )
        }

        if model.surface == .chat {
          CSMCommunicationHost(
            currentLocationProvider: model.currentCommunicationLocation,
            locationShareProvider: model.requestCommunicationLocationShare,
            voipDeviceTokenProvider: VoiceCallService.shared.currentPushTokenIfAvailable,
            expectedSubjectID: model.nativeChatExpectedSubjectID,
            onClose: model.closeNativeChat,
            onOpenCOP: model.closeNativeChat,
            onStartVoiceCall: { roomID, title, participantSubjectIDs in
              model.startNativeVoiceCall(
                roomID: roomID,
                title: title,
                participantSubjectIDs: participantSubjectIDs
              )
            }
          )
            .background(Color(.systemBackground))
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(50)
        }

        if VoiceCallService.shared.presentation.activeCall != nil {
          ActiveCallView(service: VoiceCallService.shared)
            .transition(.opacity)
            .zIndex(100)
        }
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.surface)
      .alert(
        "Hovor není dostupný",
        isPresented: Binding(
          get: { VoiceCallService.shared.presentation.lastErrorMessage != nil },
          set: { isPresented in
            if !isPresented {
              VoiceCallService.shared.presentation.clearError()
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {
          VoiceCallService.shared.presentation.clearError()
        }
      } message: {
        Text(
          VoiceCallService.shared.presentation.lastErrorMessage
            ?? "Hovor se nepodařilo připravit."
        )
      }
      .task {
        guard !model.isUITesting else { return }
        await CSMCommunicationNotifications.prepareDeviceRegistration(
          voipDeviceTokenProvider: VoiceCallService.shared.currentPushTokenIfAvailable
        )
      }
      .onReceive(NotificationCenter.default.publisher(for: .copNativeChatRequested)) { _ in
        model.openNativeChat(expectedSubjectID: nil)
      }
    case .failure(let error):
      TechnicalFallbackView(
        title: "Aplikace není nakonfigurována",
        message: error.userMessage,
        diagnosticCode: error.diagnosticCode,
        retry: nil
      )
    }
  }
}

private struct LoadingView: View {
  let environment: String
  let openChat: () -> Void

  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
        Text("Načítám mapu COP")
          .font(.headline)
        Button("Otevřít komunikaci", action: openChat)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("app.openNativeChat")
        if environment != "production" {
          Text(environment)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("app.loading")
    }
  }
}

private struct TechnicalFallbackView: View {
  let title: String
  let message: String
  let diagnosticCode: String
  let retry: (() -> Void)?
  var openChat: (() -> Void)? = nil

  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      ContentUnavailableView {
        Label(title, systemImage: "network.slash")
      } description: {
        Text(message)
      } actions: {
        if let openChat {
          Button("Otevřít komunikaci", action: openChat)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("app.openNativeChat")
        }
        if let retry {
          Button("Zkusit znovu", action: retry)
            .buttonStyle(.bordered)
        }
      }
      .padding()
      .accessibilityIdentifier("app.technicalFallback")
    }
  }
}
