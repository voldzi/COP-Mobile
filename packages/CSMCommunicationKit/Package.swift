// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CSMCommunicationKit",
    defaultLocalization: "cs",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "CSMCommunicationKit", type: .static, targets: ["CSMCommunicationKit"]),
        .library(name: "CSMNotificationCore", type: .static, targets: ["CSMNotificationCore"]),
        .library(name: "CSMVoiceCallKit", type: .static, targets: ["CSMVoiceCallKit"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/element-hq/matrix-rust-components-swift.git",
            exact: "26.09.17"
        ),
        .package(
            url: "https://github.com/livekit/client-sdk-swift.git",
            exact: "2.17.0"
        )
    ],
    targets: [
        .target(
            name: "CSMNotificationCore",
            path: "Sources/CSMNotificationCore"
        ),
        .target(
            name: "CSMCommunicationKit",
            dependencies: [
                "CSMNotificationCore",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")
            ],
            path: ".",
            sources: [
                "Apps/CSMMobile/AvatarImageSupport.swift",
                "Apps/CSMMobile/ConversationListComponents.swift",
                "Apps/CSMMobile/ConversationListModels.swift",
                "Apps/CSMMobile/ConversationListView.swift",
                "Apps/CSMMobile/ConversationRowViews.swift",
                "Apps/CSMMobile/ConversationSearchKey.swift",
                "Apps/CSMMobile/ConversationSheets.swift",
                "Apps/CSMMobile/ConversationWorkspace.swift",
                "Apps/CSMMobile/LoginView.swift",
                "Apps/CSMMobile/MatrixEncryptionRecoveryViews.swift",
                "Apps/CSMMobile/MessageAttachmentDetailSheet.swift",
                "Apps/CSMMobile/MessageComposerView.swift",
                "Apps/CSMMobile/MessageTimelineViews.swift",
                "Apps/CSMMobile/MobilePairingViews.swift",
                "Sources/CSMCore",
                "Sources/CSMDesignSystem",
                "Sources/CSMCommunicationKit"
            ],
            resources: [
                .process("Resources/Localization")
            ]
        ),
        .target(
            name: "CSMVoiceCallKit",
            dependencies: [
                "CSMCommunicationKit",
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/CSMVoiceCallKit"
        ),
        .testTarget(
            name: "CSMCommunicationKitTests",
            dependencies: ["CSMCommunicationKit", "CSMNotificationCore", "CSMVoiceCallKit"],
            path: "Tests/CSMCommunicationKitTests"
        )
    ]
)
