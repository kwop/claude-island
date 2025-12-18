//
//  TerminalAppRegistry.swift
//  ClaudeIsland
//
//  Centralized registry of known terminal applications
//

import Foundation

/// Registry of known terminal application names and bundle identifiers
struct TerminalAppRegistry: Sendable {
    /// Pure terminal app names (not IDEs with integrated terminals)
    static let pureTerminalNames: Set<String> = [
        "Terminal",
        "iTerm2",
        "iTerm",
        "Ghostty",
        "Alacritty",
        "kitty",
        "Hyper",
        "Warp",
        "WezTerm",
        "Tabby",
        "Rio",
        "Contour",
        "foot",
        "st",
        "urxvt",
        "xterm"
    ]

    /// IDE names that have integrated terminals
    static let ideNames: Set<String> = [
        "Code",           // VS Code
        "Code - Insiders",
        "Cursor",
        "Windsurf",
        "zed"
    ]

    /// All terminal app names for process matching (pure terminals + IDEs)
    static let appNames: Set<String> = pureTerminalNames.union(ideNames)

    /// Bundle identifiers for pure terminal apps (prioritized for activation)
    static let pureTerminalBundleIds: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm"
    ]

    /// Bundle identifiers for IDEs with integrated terminals
    static let ideBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed"
    ]

    /// All bundle identifiers for terminal apps (for window enumeration)
    static let bundleIdentifiers: Set<String> = Set(pureTerminalBundleIds).union(ideBundleIds)

    /// Check if an app name or command path is a known terminal (pure or IDE)
    static func isTerminal(_ appNameOrCommand: String) -> Bool {
        let lower = appNameOrCommand.lowercased()

        // Check if any known app name is contained in the command (case-insensitive)
        for name in appNames {
            if lower.contains(name.lowercased()) {
                return true
            }
        }

        // Additional checks for common patterns
        return lower.contains("terminal") || lower.contains("iterm")
    }

    /// Check if an app name or command path is a pure terminal (not an IDE)
    static func isPureTerminal(_ appNameOrCommand: String) -> Bool {
        let lower = appNameOrCommand.lowercased()

        for name in pureTerminalNames {
            if lower.contains(name.lowercased()) {
                return true
            }
        }

        return lower.contains("terminal") || lower.contains("iterm")
    }

    /// Check if a bundle identifier is a known terminal
    static func isTerminalBundle(_ bundleId: String) -> Bool {
        bundleIdentifiers.contains(bundleId)
    }

    /// Check if a bundle identifier is a pure terminal (not an IDE)
    static func isPureTerminalBundle(_ bundleId: String) -> Bool {
        pureTerminalBundleIds.contains(bundleId)
    }
}
