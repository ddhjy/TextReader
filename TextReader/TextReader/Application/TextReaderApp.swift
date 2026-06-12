import SwiftUI

enum AppDataProfile: String, CaseIterable, Identifiable, Hashable {
    case personal
    case reviewSample

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personal:
            return "日常状态"
        case .reviewSample:
            return "审核样例状态"
        }
    }

    var settingsKeyPrefix: String {
        switch self {
        case .personal:
            return ""
        case .reviewSample:
            return "reviewSample."
        }
    }

    var builtInBooks: [LibraryManager.BuiltInBook] {
        switch self {
        case .personal:
            return [.userGuide]
        case .reviewSample:
            return [.reviewSample]
        }
    }

    func documentsDirectory(baseDocumentsDirectory: URL,
                            fileManager: FileManager = .default) throws -> URL {
        switch self {
        case .personal:
            return baseDocumentsDirectory
        case .reviewSample:
            let directory = baseDocumentsDirectory.appendingPathComponent(".review-sample-profile", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    func clearPersistedData(baseDocumentsDirectory: URL,
                            fileManager: FileManager = .default,
                            defaults: UserDefaults = .standard) throws {
        guard self != .personal else { return }

        let directory = baseDocumentsDirectory.appendingPathComponent(".review-sample-profile", isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        SettingsManager(defaults: defaults, keyPrefix: settingsKeyPrefix).removeAllManagedValues()
    }
}

final class AppProfileStore {
    private let defaults: UserDefaults
    private let activeProfileKey = "activeDataProfile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var activeProfile: AppDataProfile {
        get {
            guard let rawValue = defaults.string(forKey: activeProfileKey),
                  let profile = AppDataProfile(rawValue: rawValue) else {
                return .personal
            }
            return profile
        }
        set {
            defaults.set(newValue.rawValue, forKey: activeProfileKey)
        }
    }
}

@MainActor
final class AppSessionController: ObservableObject {
    @Published private(set) var activeProfile: AppDataProfile
    @Published private(set) var viewModel: ContentViewModel
    @Published private(set) var sessionID = UUID()

    private let profileStore: AppProfileStore
    private let fileManager: FileManager
    private let documentsRootProvider: () throws -> URL

    init(profileStore: AppProfileStore = AppProfileStore(),
         fileManager: FileManager = .default,
         documentsRootProvider: (() throws -> URL)? = nil) {
        self.profileStore = profileStore
        self.fileManager = fileManager
        self.documentsRootProvider = documentsRootProvider ?? {
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw LibraryManager.LibraryError.directoryAccessFailed
            }
            return documentsDirectory
        }

        let profile = profileStore.activeProfile
        self.activeProfile = profile
        self.viewModel = Self.makeViewModel(
            for: profile,
            fileManager: fileManager,
            documentsRootProvider: self.documentsRootProvider
        )
    }

    func switchProfile(to profile: AppDataProfile) {
        guard profile != activeProfile else { return }

        viewModel.prepareForDataProfileSwitch()
        profileStore.activeProfile = profile
        activeProfile = profile
        viewModel = Self.makeViewModel(
            for: profile,
            fileManager: fileManager,
            documentsRootProvider: documentsRootProvider
        )
        sessionID = UUID()
    }

    func resetReviewSampleProfile() {
        if activeProfile == .reviewSample {
            viewModel.prepareForDataProfileSwitch()
        }

        do {
            try AppDataProfile.reviewSample.clearPersistedData(
                baseDocumentsDirectory: documentsRootProvider(),
                fileManager: fileManager
            )
        } catch {
            print("[AppSessionController] 重置审核样例状态失败: \(error)")
        }

        guard activeProfile == .reviewSample else { return }
        viewModel = Self.makeViewModel(
            for: .reviewSample,
            fileManager: fileManager,
            documentsRootProvider: documentsRootProvider
        )
        sessionID = UUID()
    }

    private static func makeViewModel(for profile: AppDataProfile,
                                      fileManager: FileManager,
                                      documentsRootProvider: @escaping () throws -> URL) -> ContentViewModel {
        let documentsDirectoryProvider: () throws -> URL = {
            let baseDirectory = try documentsRootProvider()
            return try profile.documentsDirectory(
                baseDocumentsDirectory: baseDirectory,
                fileManager: fileManager
            )
        }

        let templateDirectoryProvider: () -> URL = {
            do {
                return try documentsDirectoryProvider()
            } catch {
                fatalError("无法访问数据目录: \(error)")
            }
        }

        return ContentViewModel(
            libraryManager: LibraryManager(
                fileManager: fileManager,
                documentsDirectoryProvider: documentsDirectoryProvider,
                builtInBooks: profile.builtInBooks
            ),
            settingsManager: SettingsManager(keyPrefix: profile.settingsKeyPrefix),
            templateManager: TemplateManager(
                fileManager: fileManager,
                documentsDirectoryProvider: templateDirectoryProvider
            )
        )
    }
}

@main
struct TextReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSessionController()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: session.viewModel, session: session)
                .id(session.sessionID)
                .task(id: session.sessionID) {
                    session.viewModel.consumePendingSharedImports()
                }
                .onOpenURL { url in
                    print("[TextReaderApp] openURL: \(url)")
                    session.viewModel.handleImportedURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            session.viewModel.consumePendingSharedImports()
        }
    }
}
