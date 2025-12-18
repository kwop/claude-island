//
//  WindowFinder.swift
//  ClaudeIsland
//
//  Finds windows using yabai window manager
//

import AppKit
import Foundation

/// Information about a yabai window
struct YabaiWindow: Sendable {
    let id: Int
    let pid: Int
    let title: String
    let space: Int
    let isVisible: Bool
    let hasFocus: Bool

    nonisolated init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let pid = dict["pid"] as? Int else { return nil }

        self.id = id
        self.pid = pid
        self.title = dict["title"] as? String ?? ""
        self.space = dict["space"] as? Int ?? 0
        self.isVisible = dict["is-visible"] as? Bool ?? false
        self.hasFocus = dict["has-focus"] as? Bool ?? false
    }
}

/// Finds windows using yabai
actor WindowFinder {
    static let shared = WindowFinder()

    private var yabaiPath: String?
    private var isAvailableCache: Bool?

    private init() {}

    /// Check if yabai is available (caches result)
    func isYabaiAvailable() -> Bool {
        if let cached = isAvailableCache { return cached }

        let paths = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                yabaiPath = path
                isAvailableCache = true
                return true
            }
        }
        isAvailableCache = false
        return false
    }

    /// Get the yabai path if available
    func getYabaiPath() -> String? {
        _ = isYabaiAvailable()
        return yabaiPath
    }

    /// Get all windows from yabai
    func getAllWindows() async -> [YabaiWindow] {
        guard isYabaiAvailable(), let path = yabaiPath else { return [] }

        do {
            let output = try await ProcessExecutor.shared.run(path, arguments: ["-m", "query", "--windows"])
            guard let data = output.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return jsonArray.compactMap { YabaiWindow(from: $0) }
        } catch {
            return []
        }
    }

    /// Get the current space number
    nonisolated func getCurrentSpace(windows: [YabaiWindow]) -> Int? {
        windows.first(where: { $0.hasFocus })?.space
    }

    /// Find windows for a terminal PID
    nonisolated func findWindows(forTerminalPid pid: Int, windows: [YabaiWindow]) -> [YabaiWindow] {
        windows.filter { $0.pid == pid }
    }

    /// Find tmux window (title contains "tmux")
    nonisolated func findTmuxWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && $0.title.lowercased().contains("tmux") }
    }

    /// Find any non-Claude window for a terminal
    nonisolated func findNonClaudeWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && !$0.title.contains("✳") }
    }

    /// Find and activate the terminal application for a given Claude PID
    /// This works without yabai by finding the parent terminal app and activating it
    @MainActor
    func activateTerminalApp(forClaudePid claudePid: Int) -> Bool {
        let tree = ProcessTreeBuilder.shared.buildTree()

        // First pass: look for a pure terminal (not an IDE)
        var currentPid = claudePid
        var depth = 0

        while currentPid > 1 && depth < 30 {
            guard let info = tree[currentPid] else { break }

            // Check if this process is a pure terminal (not IDE)
            if TerminalAppRegistry.isPureTerminal(info.command) {
                if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)) {
                    return app.activate()
                }
            }

            currentPid = info.ppid
            depth += 1
        }

        // Second pass: if no pure terminal found, try any terminal (including IDE)
        currentPid = claudePid
        depth = 0

        while currentPid > 1 && depth < 30 {
            guard let info = tree[currentPid] else { break }

            if TerminalAppRegistry.isTerminal(info.command) {
                if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)) {
                    return app.activate()
                }
            }

            currentPid = info.ppid
            depth += 1
        }

        // Fallback: try to find any running pure terminal app first
        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in TerminalAppRegistry.pureTerminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                return app.activate()
            }
        }

        return false
    }

    /// Find and activate terminal app for a given working directory
    @MainActor
    func activateTerminalApp(forWorkingDirectory cwd: String) -> Bool {
        // Try to find any running pure terminal app first (prioritize real terminals over IDEs)
        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in TerminalAppRegistry.pureTerminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                return app.activate()
            }
        }
        return false
    }
}
