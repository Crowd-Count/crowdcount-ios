import SwiftUI

struct GetOnMapInfoView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "map.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.green)
                        .padding(.top, 20)

                    Text("Get Your Counter on the Map")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("1")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.green)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Request Map Placement")
                                    .font(.headline)
                                Text("Contact us to have your counter added to the public map with your business location.")
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("2")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.green)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Verify Your Business")
                                    .font(.headline)
                                Text("We'll verify your business information and counter ownership.")
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("3")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.green)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Go Live")
                                    .font(.headline)
                                Text("Once approved, your counter will appear on the map and you can create promotions!")
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Perks
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Why get on the map?")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        perkRow(
                            icon: "megaphone.fill",
                            color: .orange,
                            title: "Run Promotions",
                            description: "Create time-limited deals that show up on the map. Drive foot traffic right when you need it."
                        )

                        perkRow(
                            icon: "location.fill",
                            color: .blue,
                            title: "Be Discoverable",
                            description: "People nearby can find you on the map and get directions straight to your door."
                        )

                        perkRow(
                            icon: "person.3.fill",
                            color: .purple,
                            title: "Attract the Right Crowd",
                            description: "Some people prefer busy spots, others want somewhere quiet. Your live count helps them choose you."
                        )

                        perkRow(
                            icon: "chart.line.uptrend.xyaxis",
                            color: .green,
                            title: "Stand Out from Competitors",
                            description: "Live crowd data is something most businesses don't offer. It builds trust and curiosity."
                        )

                        perkRow(
                            icon: "clock.fill",
                            color: .teal,
                            title: "Show Real-Time Availability",
                            description: "Let customers know if now is a good time to visit — no phone call needed."
                        )
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding()
            }

            // Fixed CTA at bottom
            VStack(spacing: 12) {
                Text("Ready to get started?")
                    .font(.headline)

                Link(destination: URL(string: "mailto:info@crowdcount.tech?subject=Map%20Placement%20Request")!) {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Contact Us")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationBarTitle("Get on the Map", displayMode: .inline)
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    private func perkRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("Get on Map Info - Light") {
    NavigationView {
        GetOnMapInfoView()
            .environmentObject(AppSettings())
    }
    .preferredColorScheme(.light)
}

#Preview("Get on Map Info - Dark") {
    NavigationView {
        GetOnMapInfoView()
            .environmentObject(AppSettings())
    }
    .preferredColorScheme(.dark)
}
