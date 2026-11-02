import SwiftUI

struct ContentView: View {
    @StateObject private var model = JobViewModel()

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 16) {
                Text("Lightsail")
                    .font(.custom("Georgia", size: 48))
                    .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))

                Text("Provision Lightsail")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))

                Text("Create Ubuntu 24 in Oregon (us-west-2a), attach a static IP, and install Outline.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                HStack(spacing: 12) {
                    Button("Create cusor_instance") {
                        model.create()
                    }
                    .buttonStyle(SeaButtonStyle())
                    .disabled(model.isBusy)

                    Button("Clean up") {
                        model.cleanup()
                    }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(model.isBusy)
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 480)

            if model.showProgress {
                ProgressSheet(model: model)
            }

            if model.showMessage {
                MessageSheet(
                    title: model.messageTitle,
                    bodyText: model.messageBody,
                    onClose: model.dismissMessage
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.08, blue: 0.12),
                    Color(red: 0.05, green: 0.14, blue: 0.21),
                    Color(red: 0.04, green: 0.10, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.42, blue: 0.42).opacity(0.45), .clear],
                center: UnitPoint(x: 0.15, y: 0.2),
                startRadius: 20,
                endRadius: 320
            )
            RadialGradient(
                colors: [Color(red: 0.07, green: 0.27, blue: 0.43).opacity(0.5), .clear],
                center: UnitPoint(x: 0.85, y: 0.75),
                startRadius: 20,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

private struct SeaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.97, blue: 0.96))
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.54, green: 0.23, blue: 0.23),
                        Color(red: 0.36, green: 0.14, blue: 0.14),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    ContentView()
}
