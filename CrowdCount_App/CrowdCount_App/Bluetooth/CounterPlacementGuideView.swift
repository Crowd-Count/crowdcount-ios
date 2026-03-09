import SwiftUI

struct CounterPlacementGuideView: View {
    // Pass-through bindings for BluetoothSetupView
    @Binding var wifiSSID: String
    @Binding var wifiPassword: String
    @ObservedObject var bluetoothManager: BluetoothManager
    let sendWiFiCredentials: () -> Void
    var knownDevicePassword: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Graphic: Counter on doorway with arrows
            counterPlacementGraphic
                .padding(.bottom, 8)

            // Instructions section
            instructionsSection

            Spacer()

            // Continue button → BluetoothSetupView
            NavigationLink(destination: BluetoothSetupView(
                wifiSSID: $wifiSSID,
                wifiPassword: $wifiPassword,
                bluetoothManager: bluetoothManager,
                sendWiFiCredentials: sendWiFiCredentials,
                knownDevicePassword: knownDevicePassword
            )) {
                Text("Continue to WiFi Setup")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
        .navigationTitle("Counter Placement")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Counter Placement Graphic

    private var counterPlacementGraphic: some View {
        ZStack {
            // Doorway frame with rounded inner corners
            DoorwayShape()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 220, height: 160)

            // Counter device above doorway
            VStack(spacing: 6) {
                // The counter box
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 55, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 2)
                    )

                // Down arrow from counter to door
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)
            }
            .offset(y: -95)

            // Centering arrows pointing inward
            HStack(spacing: 40) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.green.opacity(0.8))

                // Spacer for the counter
                Color.clear.frame(width: 55)

                Image(systemName: "arrow.left")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.green.opacity(0.8))
            }
            .offset(y: -95)
        }
        .frame(height: 240)
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionRow(
                icon: "arrow.left.and.right",
                iconColor: .blue,
                text: "Center the counter above the doorway and ensure the camera isn't being blocked"
            )

            InstructionRow(
                icon: "power",
                iconColor: .green,
                text: "Make sure it's plugged in and powered"
            )

            InstructionRow(
                icon: "level",
                iconColor: .orange,
                text: "Keep the counter level (not angled)"
            )
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Doorway Shape

private struct DoorwayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let frameThickness: CGFloat = 16
        let outerCornerRadius: CGFloat = 14
        let innerCornerRadius: CGFloat = 8

        // Inner opening dimensions
        let innerX = frameThickness
        let innerY = frameThickness
        let innerWidth = rect.width - (frameThickness * 2)

        // Create outer path with only top corners rounded
        var outerPath = Path()
        outerPath.move(to: CGPoint(x: 0, y: rect.height))
        outerPath.addLine(to: CGPoint(x: 0, y: outerCornerRadius))
        outerPath.addArc(
            center: CGPoint(x: outerCornerRadius, y: outerCornerRadius),
            radius: outerCornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        outerPath.addLine(to: CGPoint(x: rect.width - outerCornerRadius, y: 0))
        outerPath.addArc(
            center: CGPoint(x: rect.width - outerCornerRadius, y: outerCornerRadius),
            radius: outerCornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        outerPath.addLine(to: CGPoint(x: rect.width, y: rect.height))
        outerPath.closeSubpath()

        path = outerPath

        // Create inner path with only top corners rounded
        var innerPath = Path()
        innerPath.move(to: CGPoint(x: innerX, y: rect.height))
        innerPath.addLine(to: CGPoint(x: innerX, y: innerY + innerCornerRadius))
        innerPath.addArc(
            center: CGPoint(x: innerX + innerCornerRadius, y: innerY + innerCornerRadius),
            radius: innerCornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        innerPath.addLine(to: CGPoint(x: innerX + innerWidth - innerCornerRadius, y: innerY))
        innerPath.addArc(
            center: CGPoint(x: innerX + innerWidth - innerCornerRadius, y: innerY + innerCornerRadius),
            radius: innerCornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        innerPath.addLine(to: CGPoint(x: innerX + innerWidth, y: rect.height))
        innerPath.closeSubpath()

        // Subtract the inner path from outer
        path = path.subtracting(innerPath)

        return path
    }
}

// MARK: - Instruction Row Component

private struct InstructionRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        CounterPlacementGuideView(
            wifiSSID: .constant(""),
            wifiPassword: .constant(""),
            bluetoothManager: BluetoothManager(),
            sendWiFiCredentials: {}
        )
    }
}
