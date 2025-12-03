import SwiftUI

struct InfoMapView: View {
    @EnvironmentObject var appSettings: AppSettings
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
    var body: some View {
        VStack {
            Text("Let us explain a bit how the map works and what some of the features are.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
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
                .padding(.top,5)
                .foregroundColor(.primary)
                .bold()
            Text("These arrows indicate wether the current location population is more or less crowded than usual at this given time and day (±25%).")
                .foregroundColor(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Text("/")
                    .padding(.top,5)
                    .font(.title3)
                    .foregroundColor(.primary)
                    .bold()
                Text("#")
                    .padding(.top,5)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .bold()
            }
            Text("Overcrowding Indicator")
                .foregroundColor(.primary)
                .padding(.top,5)
                .bold()
             Text("The number that can be displayed after the slash on certain locations shows the maximum amount of people that this location can hold (it is inputted by the business and is in no way an official or legal limit).")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Image(systemName: "ladybug.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundColor(.red)
            Text("Bug or Issue?")
                .foregroundColor(.primary)
                .padding(.top,5)
                .bold()
             Text("If a location is having an issue, please report it at \(Text("[crowdcount.tech/report](https://www.crowdcount.tech/report)")). If it's an issue on our end, feel free to send an email at \(Text("[help@crowdcount.tech](mailto:help@crowdcount.tech)")).")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .tint(.primary)
            Spacer()
            Text("\u{00A9} 2025 CrowdCount LLC. All rights reserved.")
                .foregroundColor(.secondary)
                .font(.caption2)
                .padding(2)
            Text("\(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)")) | \(Text("[Terms of Use](https://www.crowdcount.tech/legal/terms-of-use)"))")
                .foregroundColor(.secondary)
                .tint(.secondary)
                .font(.caption2)

        }
        .padding(.top)
        .padding(.leading)
        .padding(.trailing)
        .navigationBarTitle("Map Information", displayMode: .inline)
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
    }
}
