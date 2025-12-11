//
//  ExternalEditorService.swift
//  ClaudeIsland
//
//  Service for opening files in external editors (VSCode, Cursor, IntelliJ IDEA)
//

import AppKit
import Foundation

// MARK: - External Editor Enum

enum ExternalEditor: String, CaseIterable, Identifiable {
    case vscode
    case cursor
    case idea

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vscode: return "VSCode"
        case .cursor: return "Cursor"
        case .idea: return "IntelliJ IDEA"
        }
    }

    var command: String {
        switch self {
        case .vscode: return "code"
        case .cursor: return "cursor"
        case .idea: return "idea"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .idea: return "com.jetbrains.intellij"
        }
    }

    /// Build command arguments to open file at specific line
    func openFileArguments(path: String, line: Int?) -> [String] {
        switch self {
        case .vscode, .cursor:
            if let line = line {
                return ["--goto", "\(path):\(line)"]
            } else {
                return [path]
            }
        case .idea:
            if let line = line {
                return ["--line", "\(line)", path]
            } else {
                return [path]
            }
        }
    }

    /// Build command arguments to open diff view
    func diffArguments(oldPath: String, newPath: String) -> [String] {
        switch self {
        case .vscode, .cursor:
            return ["--diff", oldPath, newPath]
        case .idea:
            return ["diff", oldPath, newPath]
        }
    }
}

// MARK: - External Editor Service

struct ExternalEditorService {

    /// Common paths where CLI tools are installed
    private static let searchPaths = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/bin",
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin",
        "/Applications/Cursor.app/Contents/Resources/app/bin"
    ]

    /// Detect which editors are available on this system
    static func detectAvailableEditors() -> [ExternalEditor] {
        ExternalEditor.allCases.filter { isEditorAvailable($0) }
    }

    /// Check if a specific editor is available
    static func isEditorAvailable(_ editor: ExternalEditor) -> Bool {
        // Check if CLI command exists in PATH
        if findCommandPath(editor.command) != nil {
            return true
        }

        // Check if app bundle exists
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) != nil {
            return true
        }

        return false
    }

    /// Find the full path to a command
    private static func findCommandPath(_ command: String) -> String? {
        for basePath in searchPaths {
            let fullPath = "\(basePath)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        // Try using 'which' as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore errors
        }

        return nil
    }

    /// Open a file in the specified editor
    /// - Parameters:
    ///   - path: Absolute path to the file
    ///   - line: Optional line number to jump to
    ///   - editor: The editor to use
    static func openFile(path: String, line: Int? = nil, editor: ExternalEditor) {
        Task.detached {
            // Find the command path
            guard let commandPath = findCommandPath(editor.command) else {
                // Fallback: try to open with the app bundle
                await openWithAppBundle(path: path, editor: editor)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = editor.openFileArguments(path: path, line: line)

            // Inherit environment for proper PATH
            var environment = Foundation.ProcessInfo.processInfo.environment
            environment["PATH"] = (environment["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
            process.environment = environment

            do {
                try process.run()
                // Don't wait - let the editor open in background
            } catch {
                print("Failed to open \(editor.displayName): \(error)")
            }
        }
    }

    /// Fallback: open file using the app bundle
    @MainActor
    private static func openWithAppBundle(path: String, editor: ExternalEditor) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else {
            return
        }

        let fileURL = URL(fileURLWithPath: path)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error = error {
                print("Failed to open with \(editor.displayName): \(error)")
            }
        }
    }

    /// Find the line number where a string appears in a file
    /// - Parameters:
    ///   - searchString: The string to search for
    ///   - filePath: Path to the file
    /// - Returns: Line number (1-based) or nil if not found
    static func findLineNumber(of searchString: String, in filePath: String) -> Int? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }

        guard let range = content.range(of: searchString) else {
            return nil
        }

        // Count newlines before the match
        let prefix = content[..<range.lowerBound]
        let lineNumber = prefix.components(separatedBy: "\n").count

        return lineNumber
    }

    /// Open a diff view comparing old content with current file
    /// - Parameters:
    ///   - path: Absolute path to the current file
    ///   - oldContent: The old content to compare against
    ///   - editor: The editor to use
    static func openDiff(path: String, oldContent: String, editor: ExternalEditor) {
        Task.detached {
            // Create temp file with old content
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = (path as NSString).lastPathComponent
            let tempPath = tempDir.appendingPathComponent("old_\(fileName)").path

            do {
                try oldContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to create temp file for diff: \(error)")
                return
            }

            guard let commandPath = findCommandPath(editor.command) else {
                print("Could not find \(editor.command) command")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = editor.diffArguments(oldPath: tempPath, newPath: path)

            var environment = Foundation.ProcessInfo.processInfo.environment
            environment["PATH"] = (environment["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
            process.environment = environment

            do {
                try process.run()
            } catch {
                print("Failed to open diff in \(editor.displayName): \(error)")
            }
        }
    }
}
