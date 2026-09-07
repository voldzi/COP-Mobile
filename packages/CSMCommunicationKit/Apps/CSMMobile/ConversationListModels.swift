import SwiftUI
import UIKit

enum ConversationListNavigationMode {
    case push
    case selectionOnly
}

enum ConversationInboxFilter: String, CaseIterable, Identifiable {
    case all
    case groups
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: CSMLocalization.text("conversation.filter.all", fallback: "Vše")
        case .groups: CSMLocalization.text("conversation.filter.groups", fallback: "Skupiny")
        case .direct: CSMLocalization.text("conversation.filter.direct", fallback: "Lidé")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "bubble.left.and.bubble.right.fill"
        case .groups: "person.3.fill"
        case .direct: "person.fill"
        }
    }

    func includes(_ conversation: Conversation) -> Bool {
        switch self {
        case .all:
            true
        case .groups:
            conversation.type == .group
        case .direct:
            conversation.type == .direct
        }
    }
}


enum ConversationComposerMode: String, Identifiable {
    case group
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: CSMLocalization.text("conversation.create.group", fallback: "Nová skupina")
        case .direct: CSMLocalization.text("conversation.create.direct", fallback: "Nová zpráva")
        }
    }
}
