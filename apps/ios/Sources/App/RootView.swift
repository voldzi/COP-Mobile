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
              LoadingView {
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
  let openChat: () -> Void

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.015, green: 0.045, blue: 0.105),
          Color(red: 0.025, green: 0.11, blue: 0.17),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      Circle()
        .fill(Color.cyan.opacity(0.12))
        .frame(width: 360, height: 360)
        .blur(radius: 70)
        .offset(x: 150, y: -260)

      VStack(spacing: 0) {
        Spacer()

        Image("COPLaunchMark")
          .resizable()
          .scaledToFit()
          .frame(width: 116, height: 116)
          .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
          .shadow(color: .cyan.opacity(0.2), radius: 28, y: 10)

        Text("COP Mobile")
          .font(.system(size: 32, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .padding(.top, 24)

        Text("Připravuji situační mapu")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white.opacity(0.68))
          .padding(.top, 8)

        ProgressView()
          .tint(Color(red: 0.43, green: 0.91, blue: 0.98))
          .controlSize(.regular)
          .padding(.top, 22)

        Spacer()

        Button(action: openChat) {
          Label("Otevřít komunikaci", systemImage: "bubble.left.and.bubble.right.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .tint(Color(red: 0.12, green: 0.67, blue: 0.82))
          .accessibilityIdentifier("app.openNativeChat")
          .padding(.horizontal, 30)
          .padding(.bottom, 34)
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
