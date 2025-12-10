//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Approve all edits for this session (via tmux, sends '4' + Enter)
    func approveAllEditsInSession(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else { return }

            // Need to find the tmux target and send '4' which is "Allow all Edit in this session"
            guard let tty = session.tty else { return }

            if let target = await findTmuxTarget(tty: tty) {
                // Send '4' + Enter for "Allow all Edit in this session"
                let tmuxPath = await TmuxPathFinder.shared.getTmuxPath()
                if let path = tmuxPath {
                    let targetStr = target.targetString
                    _ = try? await ProcessExecutor.shared.run(path, arguments: ["send-keys", "-t", targetStr, "-l", "4"])
                    _ = try? await ProcessExecutor.shared.run(path, arguments: ["send-keys", "-t", targetStr, "Enter"])
                }
            }
        }
    }

    /// Find tmux target for a given tty
    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneTty = parts[1].replacingOccurrences(of: "/dev/", with: "")

                if paneTty == tty {
                    return TmuxTarget(from: target)
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    /// Deny permission with instructions for Claude
    func denyPermissionWithInstructions(sessionId: String, instructions: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Deny via socket with the instructions as reason
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: instructions
            )

            // Update session state
            await SessionStore.shared.process(
                .permissionDenied(
                    sessionId: sessionId,
                    toolUseId: permission.toolUseId,
                    reason: instructions
                )
            )
        }
    }

    /// Answer a question from Claude (for AskUserQuestion tool)
    func answerQuestion(sessionId: String, answer: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let tty = session.tty,
                  let target = await findTmuxTarget(tty: tty) else {
                return
            }

            _ = await ToolApprovalHandler.shared.sendMessage(answer, to: target)
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
