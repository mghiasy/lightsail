import Foundation
import SwiftUI

@MainActor
final class JobViewModel: ObservableObject {
    @Published var isBusy = false
    @Published var showProgress = false
    @Published var progressTitle = ""
    @Published var detail = "Starting…"
    @Published var detailKind: DetailKind = .pending
    @Published var steps: [ProgressStep] = []
    @Published var accessKey: String?
    @Published var errorText: String?
    @Published var canCloseProgress = false

    @Published var showMessage = false
    @Published var messageTitle = ""
    @Published var messageBody = ""

    enum DetailKind {
        case pending
        case ok
        case error
    }

    private let client = APIClient()

    func create() {
        Task {
            await runCreate()
        }
    }

    func cleanup() {
        Task {
            await runCleanup()
        }
    }

    func dismissProgress() {
        showProgress = false
        resetProgress()
    }

    func dismissMessage() {
        showMessage = false
    }

    private func resetProgress() {
        detail = "Starting…"
        detailKind = .pending
        accessKey = nil
        errorText = nil
        canCloseProgress = false
        steps = []
    }

    private func openProgress(title: String, steps: [ProgressStep]) {
        progressTitle = title
        self.steps = steps
        detail = "Starting…"
        detailKind = .pending
        accessKey = nil
        errorText = nil
        canCloseProgress = false
        showProgress = true
    }

    private func markStep(id: String, message: String?) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        for i in steps.indices {
            if i < index {
                steps[i].state = .done
            } else if i == index {
                steps[i].state = id == "done" ? .done : .active
            } else {
                steps[i].state = .pending
            }
        }
        if let message {
            detail = message
        }
    }

    private func finish(ok: Bool, message: String, error: String? = nil, key: String? = nil) {
        detail = message
        detailKind = ok ? .ok : .error
        canCloseProgress = true
        isBusy = false
        if let key {
            accessKey = key
        }
        if !ok {
            errorText = error ?? message
            if let active = steps.firstIndex(where: { $0.state == .active }) {
                steps[active].state = .error
            }
        } else {
            markStep(id: "done", message: message)
        }
    }

    private func runCreate() async {
        isBusy = true
        openProgress(title: "Provisioning progress", steps: CreateSteps.all)

        var sawError = false
        var lastMessage = "Done."
        var errorText: String?
        var accessKey: String?

        do {
            for try await line in client.stream(path: "/api/create-instance") {
                handleLine(
                    line,
                    sawError: &sawError,
                    lastMessage: &lastMessage,
                    errorText: &errorText,
                    accessKey: &accessKey
                )
            }
            if sawError {
                finish(ok: false, message: lastMessage, error: errorText ?? lastMessage)
            } else {
                finish(ok: true, message: lastMessage, key: accessKey)
            }
        } catch {
            finish(ok: false, message: error.localizedDescription, error: error.localizedDescription)
        }
    }

    private func runCleanup() async {
        isBusy = true
        var progressOpened = false
        var sawError = false
        var lastMessage = "Cleanup complete"
        var errorText: String?
        var notFoundMessage: String?

        do {
            for try await line in client.stream(path: "/api/cleanup-instance") {
                if line.hasPrefix("PROGRESS|") {
                    if !progressOpened {
                        openProgress(title: "Cleanup progress", steps: CleanupSteps.all)
                        progressOpened = true
                    }
                    handleProgress(line, lastMessage: &lastMessage, sawError: &sawError, errorText: &errorText)
                    continue
                }

                if line.hasPrefix("ERROR:") || line.hasPrefix("FAILED") {
                    sawError = true
                    errorText = line.replacingOccurrences(of: "ERROR:", with: "").trimmingCharacters(in: .whitespaces)
                    lastMessage = errorText ?? line
                    continue
                }

                if let payload = decodeJSON(line) {
                    if payload["notFound"] as? Bool == true {
                        notFoundMessage = (payload["error"] as? String)
                            ?? "Instance cusor_instance does not exist."
                        continue
                    }
                    if payload["ok"] as? Bool == false, let err = payload["error"] as? String {
                        sawError = true
                        errorText = err
                        lastMessage = err.split(separator: "\n").first.map(String.init) ?? err
                        continue
                    }
                    if payload["ok"] as? Bool == true, payload["cleaned"] as? Bool == true {
                        lastMessage = "Cleanup complete"
                    }
                }
            }

            if let notFoundMessage {
                isBusy = false
                messageTitle = "Cleanup"
                messageBody = notFoundMessage
                showMessage = true
                return
            }

            if !progressOpened {
                openProgress(title: "Cleanup progress", steps: CleanupSteps.all)
            }

            if sawError {
                finish(ok: false, message: lastMessage, error: errorText ?? lastMessage)
            } else {
                finish(ok: true, message: lastMessage)
            }
        } catch {
            isBusy = false
            messageTitle = "Cleanup"
            messageBody = error.localizedDescription
            showMessage = true
        }
    }

    private func handleLine(
        _ line: String,
        sawError: inout Bool,
        lastMessage: inout String,
        errorText: inout String?,
        accessKey: inout String?
    ) {
        if line.hasPrefix("ERROR:") {
            sawError = true
            errorText = line.replacingOccurrences(of: "ERROR:", with: "").trimmingCharacters(in: .whitespaces)
            lastMessage = errorText ?? line
            return
        }
        if line.hasPrefix("FAILED") {
            sawError = true
            errorText = line
            lastMessage = line
            return
        }
        if line.hasPrefix("PROGRESS|") {
            handleProgress(line, lastMessage: &lastMessage, sawError: &sawError, errorText: &errorText)
            return
        }
        if line.hasPrefix("ss://") || line.hasPrefix("ssconf://") {
            accessKey = line
            lastMessage = "Access key ready"
            return
        }
        if let payload = decodeJSON(line) {
            if payload["ok"] as? Bool == false, let err = payload["error"] as? String {
                sawError = true
                errorText = err
                lastMessage = err.split(separator: "\n").first.map(String.init) ?? err
                return
            }
            if payload["ok"] as? Bool == true, let key = payload["accessKey"] as? String {
                accessKey = key
                lastMessage = "Access key ready"
            }
        }
    }

    private func handleProgress(
        _ line: String,
        lastMessage: inout String,
        sawError: inout Bool,
        errorText: inout String?
    ) {
        let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return }
        let step = String(parts[1])
        let message = parts.count > 2 ? String(parts[2]) : ""
        if step == "error" {
            sawError = true
            errorText = message
            lastMessage = message.isEmpty ? "Operation failed" : message
            return
        }
        markStep(id: step, message: message.isEmpty ? nil : message)
        if !message.isEmpty {
            lastMessage = message
        }
    }

    private func decodeJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
}
