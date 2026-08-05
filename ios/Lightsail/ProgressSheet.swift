import SwiftUI

struct ProgressSheet: View {
    @ObservedObject var model: JobViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    if model.canCloseProgress {
                        model.dismissProgress()
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(model.progressTitle)
                    .font(.custom("Georgia", size: 28))
                    .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))

                Text(model.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.steps) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(dotColor(step.state))
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                Text(step.label)
                                    .font(.system(size: 15))
                                    .foregroundStyle(labelColor(step.state))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)

                if let accessKey = model.accessKey {
                    Text(accessKey)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color(red: 0.56, green: 0.83, blue: 0.81))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(red: 0.56, green: 0.83, blue: 0.81).opacity(0.22))
                        )
                        .textSelection(.enabled)
                }

                if let errorText = model.errorText, model.detailKind == .error {
                    Text(errorText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color(red: 0.94, green: 0.66, blue: 0.63))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.28))
                        .textSelection(.enabled)
                }

                if model.canCloseProgress {
                    Button("Close") {
                        model.dismissProgress()
                    }
                    .buttonStyle(CloseButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.16, blue: 0.20).opacity(0.96),
                        Color(red: 0.04, green: 0.09, blue: 0.13).opacity(0.98),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(20)
        }
    }

    private var detailColor: Color {
        switch model.detailKind {
        case .ok: return Color(red: 0.56, green: 0.83, blue: 0.81)
        case .error: return Color(red: 0.94, green: 0.66, blue: 0.63)
        case .pending: return Color.white.opacity(0.72)
        }
    }

    private func dotColor(_ state: ProgressStep.StepState) -> Color {
        switch state {
        case .pending: return Color.white.opacity(0.22)
        case .active, .done: return Color(red: 0.56, green: 0.83, blue: 0.81)
        case .error: return Color(red: 0.94, green: 0.66, blue: 0.63)
        }
    }

    private func labelColor(_ state: ProgressStep.StepState) -> Color {
        switch state {
        case .pending: return Color.white.opacity(0.38)
        case .active: return Color(red: 0.95, green: 0.97, blue: 0.96)
        case .done: return Color(red: 0.56, green: 0.83, blue: 0.81).opacity(0.95)
        case .error: return Color(red: 0.94, green: 0.66, blue: 0.63)
        }
    }
}

struct MessageSheet: View {
    let title: String
    let bodyText: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.custom("Georgia", size: 28))
                    .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))

                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.72))

                Button("OK", action: onClose)
                    .buttonStyle(CloseButtonStyle())
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.16, blue: 0.20).opacity(0.96),
                        Color(red: 0.04, green: 0.09, blue: 0.13).opacity(0.98),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(20)
        }
    }
}

private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.42, blue: 0.42),
                        Color(red: 0.06, green: 0.27, blue: 0.27),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
