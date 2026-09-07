// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CSMCommunicationKit",
    defaultLocalization: "cs",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "CSMCommunicationKit", targets: ["CSMCommunicationKit"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/element-hq/matrix-rust-components-swift.git",
            exact: "26.09.07"
        )
    ],
    targets: [
        .target(
            name: "CSMCommunicationKit",
            dependencies: [
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
        .testTarget(
            name: "CSMCommunicationKitTests",
            dependencies: ["CSMCommunicationKit"],
            path: "Tests/CSMCommunicationKitTests"
        )
    ]
)
