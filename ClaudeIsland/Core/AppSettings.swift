//
//  AppSettings.swift
//  ClaudeIsland
//
//  Centralized app settings using UserDefaults
//

import Foundation
import Combine
import SwiftUI

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let showToolResultDetails = "showToolResultDetails"
        static let answerQuestionsInUI = "answerQuestionsInUI"
        static let mascotColor = "mascotColor"
        static let preferredEditor = "preferredEditor"
    }

    // MARK: - Mascot Colors

    // TODO: Consider adding more mascot colors in a future update
    // Ideas: purple, yellow, pink, white
    static let mascotColors: [(id: String, name: String, color: Color)] = [
        ("orange", "Orange", TerminalColors.prompt),
        ("blue", "Bleu", TerminalColors.blue),
        ("green", "Vert", TerminalColors.green),
        ("magenta", "Magenta", TerminalColors.magenta),
        ("cyan", "Cyan", TerminalColors.cyan),
        ("red", "Rouge", TerminalColors.red)
    ]

    // MARK: - Settings

    /// Whether to show detailed result summaries under tool calls in chat
    @Published var showToolResultDetails: Bool {
        didSet {
            defaults.set(showToolResultDetails, forKey: Keys.showToolResultDetails)
        }
    }

    /// Whether to answer AskUserQuestion prompts directly in the UI (vs terminal)
    @Published var answerQuestionsInUI: Bool {
        didSet {
            defaults.set(answerQuestionsInUI, forKey: Keys.answerQuestionsInUI)
        }
    }

    /// The selected mascot color ID
    @Published var mascotColor: String {
        didSet {
            defaults.set(mascotColor, forKey: Keys.mascotColor)
        }
    }

    /// The actual Color value for the mascot
    var mascotColorValue: Color {
        Self.mascotColors.first { $0.id == mascotColor }?.color ?? TerminalColors.prompt
    }

    /// The preferred external editor ID (vscode, cursor, idea)
    @Published var preferredEditor: String {
        didSet {
            defaults.set(preferredEditor, forKey: Keys.preferredEditor)
        }
    }

    /// The actual ExternalEditor value, or nil if none available
    var preferredEditorValue: ExternalEditor? {
        ExternalEditor(rawValue: preferredEditor)
    }

    /// Available editors on this system (cached)
    @Published private(set) var availableEditors: [ExternalEditor] = []

    /// Refresh the list of available editors
    func refreshAvailableEditors() {
        availableEditors = ExternalEditorService.detectAvailableEditors()

        // If current preference is not available, switch to first available
        if preferredEditorValue == nil || !availableEditors.contains(where: { $0.rawValue == preferredEditor }) {
            if let first = availableEditors.first {
                preferredEditor = first.rawValue
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Default to true for new users
        if defaults.object(forKey: Keys.showToolResultDetails) == nil {
            defaults.set(true, forKey: Keys.showToolResultDetails)
        }
        self.showToolResultDetails = defaults.bool(forKey: Keys.showToolResultDetails)

        // Default to true for answering questions in UI
        if defaults.object(forKey: Keys.answerQuestionsInUI) == nil {
            defaults.set(true, forKey: Keys.answerQuestionsInUI)
        }
        self.answerQuestionsInUI = defaults.bool(forKey: Keys.answerQuestionsInUI)

        // Default to orange for mascot color
        if defaults.object(forKey: Keys.mascotColor) == nil {
            defaults.set("orange", forKey: Keys.mascotColor)
        }
        self.mascotColor = defaults.string(forKey: Keys.mascotColor) ?? "orange"

        // Default to vscode for preferred editor
        self.preferredEditor = defaults.string(forKey: Keys.preferredEditor) ?? "vscode"

        // Detect available editors
        refreshAvailableEditors()
    }
}
