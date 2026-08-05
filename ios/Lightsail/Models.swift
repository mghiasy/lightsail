import Foundation

struct ProgressStep: Identifiable, Equatable {
    let id: String
    let label: String
    var state: StepState = .pending

    enum StepState: Equatable {
        case pending
        case active
        case done
        case error
    }
}

enum JobKind {
    case create
    case cleanup
}

struct CreateSteps {
    static let all: [ProgressStep] = [
        .init(id: "create", label: "Creating instance"),
        .init(id: "created", label: "Instance created"),
        .init(id: "waiting", label: "Waiting for running"),
        .init(id: "running", label: "Instance running"),
        .init(id: "ip_create", label: "Creating static IP"),
        .init(id: "ip_created", label: "Static IP created"),
        .init(id: "ip_attach", label: "Attaching static IP"),
        .init(id: "ip_attached", label: "Static IP attached"),
        .init(id: "ssh", label: "SSH into server"),
        .init(id: "outline", label: "Install Outline (+ Docker)"),
        .init(id: "firewall", label: "Open Lightsail firewall ports"),
        .init(id: "outline_manager", label: "Open Outline Manager + paste JSON"),
        .init(id: "access_key", label: "Done → share Key 0 → copy access key"),
        .init(id: "done", label: "Complete"),
    ]
}

struct CleanupSteps {
    static let all: [ProgressStep] = [
        .init(id: "stop", label: "Stopping instance"),
        .init(id: "stopped", label: "Instance stopped"),
        .init(id: "delete_instance", label: "Deleting instance"),
        .init(id: "instance_deleted", label: "Instance deleted"),
        .init(id: "delete_ip", label: "Deleting static IP"),
        .init(id: "ip_deleted", label: "Static IP deleted"),
        .init(id: "done", label: "Cleanup complete"),
    ]
}
