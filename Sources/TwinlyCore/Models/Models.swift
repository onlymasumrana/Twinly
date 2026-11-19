import Foundation

public enum AppStrategy: String, Codable, CaseIterable {
    case electronChromium = "electronChromium"
    case genericNonSandboxed = "genericNonSandboxed"
    case firefoxGecko = "firefoxGecko"
    case sandboxedUnsupported = "sandboxedUnsupported"

    public var displayName: String {
        switch self {
        case .electronChromium:
            return "Chromium-based"
        case .genericNonSandboxed:
            return "Standard app"
        case .firefoxGecko:
            return "Firefox-based"
        case .sandboxedUnsupported:
            return "Not supported"
        }
    }

    public var isolationSummary: String {
        switch self {
        case .electronChromium:
            return "Gets its own data folder, so logins stay separate."
        case .genericNonSandboxed:
            return "Gets its own Library folder for settings and data."
        case .firefoxGecko:
            return "Gets its own Firefox profile folder, so logins and tabs stay separate."
        case .sandboxedUnsupported:
            return "macOS locks this app's data to one copy."
        }
    }
}

public struct AppAnalysis: Identifiable, Hashable {
    public var id: String { appURL.path }
    public let appURL: URL
    public let appName: String
    public let bundleIdentifier: String
    public let executablePath: String
    public let strategy: AppStrategy
    public let frameworks: [String]
    public let isSandboxed: Bool
    public let iconURL: URL?
    public let explanation: String
    public let warning: String?

    public init(
        appURL: URL,
        appName: String,
        bundleIdentifier: String,
        executablePath: String,
        strategy: AppStrategy,
        frameworks: [String] = [],
        isSandboxed: Bool = false,
        iconURL: URL? = nil,
        explanation: String,
        warning: String? = nil
    ) {
        self.appURL = appURL
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.strategy = strategy
        self.frameworks = frameworks
        self.isSandboxed = isSandboxed
        self.iconURL = iconURL
        self.explanation = explanation
        self.warning = warning
    }
}

public struct Profile: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var originalAppPath: String
    public var originalBundleId: String
    public var appName: String
    public var strategy: AppStrategy
    public var badgeColorHex: String
    public var badgeText: String
    public var profileDirectory: String
    public var wrapperAppPath: String
    public var customArgs: [String]
    public var customEnv: [String: String]
    public var createdAt: Date
    public var lastLaunchedAt: Date?
    public var separateDockIcon: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, originalAppPath, originalBundleId, appName, strategy, badgeColorHex, badgeText, profileDirectory, wrapperAppPath, customArgs, customEnv, createdAt, lastLaunchedAt, separateDockIcon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        originalAppPath = try c.decode(String.self, forKey: .originalAppPath)
        originalBundleId = try c.decode(String.self, forKey: .originalBundleId)
        appName = try c.decode(String.self, forKey: .appName)
        strategy = try c.decode(AppStrategy.self, forKey: .strategy)
        badgeColorHex = try c.decodeIfPresent(String.self, forKey: .badgeColorHex) ?? "#3B82F6"
        badgeText = try c.decodeIfPresent(String.self, forKey: .badgeText) ?? "2"
        profileDirectory = try c.decode(String.self, forKey: .profileDirectory)
        wrapperAppPath = try c.decode(String.self, forKey: .wrapperAppPath)
        customArgs = try c.decodeIfPresent([String].self, forKey: .customArgs) ?? []
        customEnv = try c.decodeIfPresent([String: String].self, forKey: .customEnv) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSinceReferenceDate: 0)
        lastLaunchedAt = try c.decodeIfPresent(Date.self, forKey: .lastLaunchedAt) ?? nil
        separateDockIcon = try c.decodeIfPresent(Bool.self, forKey: .separateDockIcon) ?? nil
    }

    public init(
        id: UUID = UUID(),
        name: String,
        originalAppPath: String,
        originalBundleId: String,
        appName: String,
        strategy: AppStrategy,
        badgeColorHex: String = "#3B82F6",
        badgeText: String = "2",
        profileDirectory: String,
        wrapperAppPath: String,
        customArgs: [String] = [],
        customEnv: [String: String] = [:],
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil,
        separateDockIcon: Bool? = nil
    ) {
        self.separateDockIcon = separateDockIcon
        self.id = id
        self.name = name
        self.originalAppPath = originalAppPath
        self.originalBundleId = originalBundleId
        self.appName = appName
        self.strategy = strategy
        self.badgeColorHex = badgeColorHex
        self.badgeText = badgeText
        self.profileDirectory = profileDirectory
        self.wrapperAppPath = wrapperAppPath
        self.customArgs = customArgs
        self.customEnv = customEnv
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
    }
}

public enum CLIPreset: String, Codable, CaseIterable {
    case claudeCode = "claudeCode"
    case codexCLI = "codexCLI"
    case ghCLI = "ghCLI"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code (claude)"
        case .codexCLI: return "Codex CLI (codex)"
        case .ghCLI: return "GitHub CLI (gh)"
        case .custom: return "Custom CLI Tool"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex"
        case .ghCLI: return "GitHub CLI"
        case .custom: return "Other"
        }
    }

    public var defaultEnvVar: String {
        switch self {
        case .claudeCode: return "CLAUDE_CONFIG_DIR"
        case .codexCLI: return "CODEX_HOME"
        case .ghCLI: return "GH_CONFIG_DIR"
        case .custom: return "CONFIG_DIR"
        }
    }

    public var defaultBinaryName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codexCLI: return "codex"
        case .ghCLI: return "gh"
        case .custom: return ""
        }
    }

    public var defaultCommandPrefix: String {
        switch self {
        case .claudeCode: return "claude"
        case .codexCLI: return "codex"
        case .ghCLI: return "gh"
        case .custom: return "tool"
        }
    }
}

public struct CLIProfile: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var commandName: String
    public var preset: CLIPreset
    public var configEnvVar: String
    public var profileDirectory: String
    public var realBinaryPath: String
    public var wrapperScriptPath: String
    public var customEnv: [String: String]
    public var createdAt: Date
    public var lastLaunchedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, name, commandName, preset, configEnvVar, profileDirectory, realBinaryPath, wrapperScriptPath, customEnv, createdAt, lastLaunchedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        commandName = try c.decode(String.self, forKey: .commandName)
        preset = try c.decode(CLIPreset.self, forKey: .preset)
        configEnvVar = try c.decode(String.self, forKey: .configEnvVar)
        profileDirectory = try c.decode(String.self, forKey: .profileDirectory)
        realBinaryPath = try c.decode(String.self, forKey: .realBinaryPath)
        wrapperScriptPath = try c.decode(String.self, forKey: .wrapperScriptPath)
        customEnv = try c.decodeIfPresent([String: String].self, forKey: .customEnv) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSinceReferenceDate: 0)
        lastLaunchedAt = try c.decodeIfPresent(Date.self, forKey: .lastLaunchedAt) ?? nil
    }

    public init(
        id: UUID = UUID(),
        name: String,
        commandName: String,
        preset: CLIPreset,
        configEnvVar: String,
        profileDirectory: String,
        realBinaryPath: String,
        wrapperScriptPath: String,
        customEnv: [String: String] = [:],
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.commandName = commandName
        self.preset = preset
        self.configEnvVar = configEnvVar
        self.profileDirectory = profileDirectory
        self.realBinaryPath = realBinaryPath
        self.wrapperScriptPath = wrapperScriptPath
        self.customEnv = customEnv
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
    }
}

public struct LauncherConfig: Codable {
    public var version: Int
    public var profileId: UUID
    public var profileName: String
    public var originalAppPath: String
    public var executablePath: String
    public var strategy: String
    public var profileDirectory: String
    public var arguments: [String]
    public var environment: [String: String]
    public var separateDockIcon: Bool?

    private enum CodingKeys: String, CodingKey {
        case version, profileId, profileName, originalAppPath, executablePath, strategy, profileDirectory, arguments, environment, separateDockIcon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profileId = try c.decode(UUID.self, forKey: .profileId)
        profileName = try c.decode(String.self, forKey: .profileName)
        originalAppPath = try c.decode(String.self, forKey: .originalAppPath)
        executablePath = try c.decode(String.self, forKey: .executablePath)
        strategy = try c.decode(String.self, forKey: .strategy)
        profileDirectory = try c.decode(String.self, forKey: .profileDirectory)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        separateDockIcon = try c.decodeIfPresent(Bool.self, forKey: .separateDockIcon) ?? nil
    }

    public init(
        version: Int = 1,
        profileId: UUID,
        profileName: String,
        originalAppPath: String,
        executablePath: String,
        strategy: String,
        profileDirectory: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        separateDockIcon: Bool? = nil
    ) {
        self.separateDockIcon = separateDockIcon
        self.version = version
        self.profileId = profileId
        self.profileName = profileName
        self.originalAppPath = originalAppPath
        self.executablePath = executablePath
        self.strategy = strategy
        self.profileDirectory = profileDirectory
        self.arguments = arguments
        self.environment = environment
    }
}
