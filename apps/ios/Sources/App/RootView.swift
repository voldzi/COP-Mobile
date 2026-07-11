import SwiftUI

struct RootView: View {
  let model: AppModel

  var body: some View {
    switch model.configuration {
    case .success(let configuration):
      ZStack {
        WebHostView(configuration: configuration, model: model)

        switch model.phase {
        case .loading:
          LoadingView(environment: configuration.environment)
        case .webContent:
          EmptyView()
        case .offlineFallback(let code):
          TechnicalFallbackView(
            title: "COP zatím není dostupný",
            message:
              "Zkontrolujte připojení. Pokud byl COP na tomto zařízení dříve načten, WebKit se při dalším pokusu pokusí použít bezpečně uložený webový shell.",
            diagnosticCode: code,
            retry: model.retry
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

  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
        Text("Načítám COP")
          .font(.headline)
        if environment != "production" {
          Text(environment)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }
}

private struct TechnicalFallbackView: View {
  let title: String
  let message: String
  let diagnosticCode: String
  let retry: (() -> Void)?

  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      ContentUnavailableView {
        Label(title, systemImage: "network.slash")
      } description: {
        Text(message)
      } actions: {
        if let retry {
          Button("Zkusit znovu", action: retry)
            .buttonStyle(.borderedProminent)
        }
        Text("Diagnostika \(diagnosticCode)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      .padding()
    }
  }
}
