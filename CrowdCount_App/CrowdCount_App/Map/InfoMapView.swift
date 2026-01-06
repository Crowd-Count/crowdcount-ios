import SwiftUI

struct InfoMapView: View {
    @EnvironmentObject var appSettings: AppSettings
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Let us explain a bit how the map works and what some of the features are.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Comparisons
                VStack(spacing: 5) {
                    HStack {
                        Image(systemName: "arrow.up")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                            .foregroundColor(.green)
                        Image(systemName: "arrow.down")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                            .foregroundColor(.red)
                    }
                    Text("Comparisons")
                        .foregroundColor(.primary)
                        .bold()
                    Text("These arrows indicate wether the current location population is more or less crowded than usual (±25%).")
                        .foregroundColor(.secondary)
                        .tint(.primary)
                        .multilineTextAlignment(.center)
                }

                // Overcrowding Indicator
                VStack(spacing: 5) {
                    HStack {
                        Text("/")
                            .font(.title3)
                            .foregroundColor(.primary)
                            .bold()
                        Text("#")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .bold()
                    }
                    Text("Overcrowding Indicator")
                        .foregroundColor(.primary)
                        .bold()
                    Text("The number that can be displayed after the slash on certain locations shows the maximum amount of people that this location can hold (it is inputted by the business and is in no way an official or legal limit).")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Promotions
                VStack(spacing: 5) {
                    Image(systemName: "megaphone.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.blue)
                    Text("Promotions")
                        .foregroundColor(.primary)
                        .bold()
                    Text("The promotions carousel at the bottom of the map displays sponsored content from local businesses. All promotions are reviewed and approved by our team before appearing. Each promotion runs for a set duration shown by the countdown timer. Promotions are sorted by distance, so you'll see the closest ones first.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .tint(.primary)
                }

                // Bug or Issue
                VStack(spacing: 5) {
                    Image(systemName: "ladybug.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.red)
                    Text("Bug or Issue?")
                        .foregroundColor(.primary)
                        .bold()
                    Text("If a location is having an issue, please report it at \(Text("[crowdcount.tech/report](https://www.crowdcount.tech/report)")). If it's an issue on our end, feel free to send an email at \(Text("[help@crowdcount.tech](mailto:help@crowdcount.tech)")).")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .tint(.primary)
                }

                // Footer
                VStack(spacing: 2) {
                    Text("\u{00A9} 2026 CrowdCount LLC. All rights reserved.")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    Text("\(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)")) | \(Text("[Terms of Use](https://www.crowdcount.tech/legal/terms-of-use)"))")
                        .foregroundColor(.secondary)
                        .tint(.secondary)
                        .font(.caption2)
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .navigationBarTitle("Map Information", displayMode: .inline)
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }
}
