import Foundation
import SwiftUI

@MainActor
struct ActiveCallView: View {
  let service: VoiceCallService
  @State private var showingParticipantPicker = false

  private var state: VoiceCallPresentationState { service.presentation }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.025, green: 0.08, blue: 0.11),
          Color(red: 0.04, green: 0.20, blue: 0.19),
          Color(red: 0.015, green: 0.05, blue: 0.075),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      if let call = state.activeCall {
        callContent(call)
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
      }

      if state.isProximityCovered {
        Color.black
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .zIndex(100)
          .accessibilityHidden(true)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: state.isProximityCovered)
    .animation(.easeInOut(duration: 0.25), value: state.activeCall?.phase)
    .preferredColorScheme(.dark)
    .accessibilityIdentifier("nativeCall.active")
    .sheet(isPresented: $showingParticipantPicker) {
      if let call = state.activeCall {
        CallParticipantPicker(
          participants: call.eligibleParticipants,
          maximumSelection: max(0, 6 - call.participants.filter(\.connected).count),
          onInvite: service.addParticipants
        )
      }
    }
  }

  private func callContent(_ call: VoiceCallPresentation) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "shield.lefthalf.filled")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(red: 0.68, green: 0.92, blue: 0.64))
        Text("COP HOVOR")
          .font(.caption.weight(.bold))
          .tracking(1.4)
          .foregroundStyle(.white.opacity(0.75))
        Spacer()
        Text(state.routeLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.72))
      }
      .padding(.horizontal, 24)
      .padding(.top, 18)

      Spacer(minLength: 36)

      ZStack {
        Circle()
          .fill(.white.opacity(0.08))
          .frame(width: 170, height: 170)
        Circle()
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
          .frame(width: 150, height: 150)
        Text(initials(call.title))
          .font(.system(size: 52, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
      }
      .accessibilityHidden(true)

      Text(call.title)
        .font(.system(size: 31, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 30)
        .padding(.top, 26)

      callStatus(call)
        .padding(.top, 10)

      if call.kind == .group {
        Text(groupParticipantSummary(call))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white.opacity(0.62))
          .padding(.top, 8)
      }

      Spacer(minLength: 42)

      HStack(spacing: 30) {
        CallControlButton(
          title: state.isMuted ? "Zapnout" : "Ztlumit",
          systemImage: state.isMuted ? "mic.slash.fill" : "mic.fill",
          selected: state.isMuted,
          action: service.toggleMute
        )
        CallControlButton(
          title: "Zvuk",
          systemImage: state.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
          selected: state.isSpeakerEnabled,
          action: service.toggleSpeaker
        )
        if call.kind == .group,
          call.phase == .connected,
          !call.eligibleParticipants.isEmpty,
          call.participants.filter(\.connected).count < 6
        {
          CallControlButton(
            title: "Přidat",
            systemImage: "person.badge.plus",
            selected: false,
            action: { showingParticipantPicker = true }
          )
        }
      }

      HStack(spacing: 34) {
        if call.direction == .incoming && call.phase == .ringing {
          CallPrimaryButton(
            title: "Přijmout",
            systemImage: "phone.fill",
            color: Color(red: 0.10, green: 0.68, blue: 0.43),
            action: service.answerActiveCall
          )
        }
        CallPrimaryButton(
          title: call.direction == .incoming && call.phase == .ringing ? "Odmítnout" : "Ukončit",
          systemImage: "phone.down.fill",
          color: Color(red: 0.90, green: 0.20, blue: 0.22),
          action: service.endActiveCall
        )
      }
      .padding(.top, 38)
      .padding(.bottom, 38)
    }
  }

  @ViewBuilder
  private func callStatus(_ call: VoiceCallPresentation) -> some View {
    if call.phase == .connected, let connectedAt = call.connectedAt {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(elapsedTime(from: connectedAt, to: context.date))
          .font(.title3.monospacedDigit().weight(.medium))
          .foregroundStyle(.white.opacity(0.82))
          .accessibilityLabel("Délka hovoru \(elapsedTime(from: connectedAt, to: context.date))")
      }
    } else {
      HStack(spacing: 8) {
        if call.phase == .connecting {
          ProgressView()
            .tint(.white.opacity(0.8))
            .controlSize(.small)
        }
        Text(statusText(call))
          .font(.body.weight(.medium))
          .foregroundStyle(.white.opacity(0.76))
      }
    }
  }

  private func statusText(_ call: VoiceCallPresentation) -> String {
    switch call.phase {
    case .ringing:
      call.direction == .incoming ? "Příchozí hlasový hovor" : "Vyzvánění"
    case .connecting:
      "Spojuji hovor"
    case .connected:
      "Spojeno"
    case .ended:
      "Hovor ukončen"
    case .failed:
      "Hovor se nepodařilo spojit"
    }
  }

  private func groupParticipantSummary(_ call: VoiceCallPresentation) -> String {
    let count = max(1, call.participants.filter(\.connected).count)
    return count == 1 ? "1 účastník" : count < 5 ? "\(count) účastníci" : "\(count) účastníků"
  }

  private func initials(_ title: String) -> String {
    let words = title.split(whereSeparator: { $0.isWhitespace }).prefix(2)
    let value = words.compactMap(\.first).map(String.init).joined()
    return value.isEmpty ? "COP" : value.uppercased()
  }

  private func elapsedTime(from start: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainder = seconds % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
      : String(format: "%02d:%02d", minutes, remainder)
  }
}

private struct CallParticipantPicker: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selectedUserIDs = Set<String>()

  let participants: [VoiceCallParticipant]
  let maximumSelection: Int
  let onInvite: ([String]) -> Void

  var body: some View {
    NavigationStack {
      List(participants) { participant in
        Button {
          toggle(participant.userID)
        } label: {
          HStack(spacing: 12) {
            Text(initials(participant.displayName))
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 40, height: 40)
              .background(Color.accentColor, in: Circle())
            Text(participant.displayName)
              .foregroundStyle(.primary)
            Spacer()
            Image(systemName: selectedUserIDs.contains(participant.userID) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(selectedUserIDs.contains(participant.userID) ? Color.accentColor : .secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .navigationTitle("Přidat do hovoru")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Zrušit") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Pozvat") {
            onInvite(Array(selectedUserIDs))
            dismiss()
          }
          .disabled(selectedUserIDs.isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func toggle(_ userID: String) {
    if selectedUserIDs.remove(userID) != nil { return }
    guard selectedUserIDs.count < maximumSelection else { return }
    selectedUserIDs.insert(userID)
  }

  private func initials(_ title: String) -> String {
    let value = title.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first).map(String.init).joined()
    return value.isEmpty ? "COP" : value.uppercased()
  }
}

private struct CallControlButton: View {
  let title: String
  let systemImage: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 9) {
        Image(systemName: systemImage)
          .font(.system(size: 23, weight: .semibold))
          .frame(width: 64, height: 64)
          .background(selected ? Color.white : Color.white.opacity(0.13), in: Circle())
          .foregroundStyle(selected ? Color.black : Color.white)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.88))
      }
      .frame(width: 88)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

private struct CallPrimaryButton: View {
  let title: String
  let systemImage: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 10) {
        Image(systemName: systemImage)
          .font(.system(size: 27, weight: .bold))
          .frame(width: 76, height: 76)
          .background(color, in: Circle())
          .foregroundStyle(.white)
          .shadow(color: color.opacity(0.35), radius: 18, y: 8)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.9))
      }
      .frame(width: 108)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
