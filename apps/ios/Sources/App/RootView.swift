import CSMCommunicationKit
import CSMVoiceCallKit
import SwiftUI

struct RootView: View {
  let model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    switch model.configuration {
    case .success(let configuration):
      ZStack {
        Group {
          if !model.isUITesting {
            WebHostView(configuration: configuration, model: model)
          }

          if model.surface != .chat {
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
          }
        }
        .allowsHitTesting(model.surface != .chat)
        .accessibilityHidden(model.surface == .chat)

        if model.surface == .chat {
          CSMCommunicationHost(
            currentLocationProvider: model.currentCommunicationLocation,
            locationShareProvider: model.requestCommunicationLocationShare,
            voipDeviceTokenProvider: VoiceCallService.shared.currentPushTokenIfAvailable,
            expectedSubjectID: model.nativeChatExpectedSubjectID,
            onClose: model.closeNativeChat,
            onOpenCOP: model.closeNativeChat,
            onStartVoiceCall: { roomID, title, participantSubjectIDs, avatarDataURL in
              model.startNativeVoiceCall(
                roomID: roomID,
                title: title,
                participantSubjectIDs: participantSubjectIDs,
                avatarDataURL: avatarDataURL
              )
            }
          )
            .background(Color(.systemBackground))
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(50)
        }

        if VoiceCallService.shared.hasActiveCall {
          ActiveCallView(service: VoiceCallService.shared)
            .transition(.opacity)
            .zIndex(100)
        }
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.surface)
      .alert(
        "Hovor není dostupný",
        isPresented: Binding(
          get: { VoiceCallService.shared.lastErrorMessage != nil },
          set: { isPresented in
            if !isPresented {
              VoiceCallService.shared.clearCallError()
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {
          VoiceCallService.shared.clearCallError()
        }
      } message: {
        Text(
          VoiceCallService.shared.lastErrorMessage
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
      VStack(spacing: 20) {
        ContentUnavailableView {
          Label(title, systemImage: "network.slash")
        } description: {
          Text(message)
        }
        .fixedSize(horizontal: false, vertical: true)

        VStack(spacing: 12) {
          if let openChat {
            Button("Otevřít komunikaci", action: openChat)
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("app.openNativeChat")
          }
          if let retry {
            Button("Zkusit znovu", action: retry)
              .buttonStyle(.bordered)
              .accessibilityIdentifier("app.retryMap")
          }
        }
      }
      .padding()
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("app.technicalFallback")
    }
  }
}
