import SwiftUI

struct InformationView: View {
    @EnvironmentObject var appSettings: AppSettings
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
    var body: some View {
        VStack {
            Spacer()
            Image(appSettings.isDarkMode ? .transparentLogo : .transparentLogoBlack)
                .resizable()
                .scaledToFit()
                .frame(width: 75, height: 75)
                .foregroundColor(.secondary)
//                .padding(5)
            Text("CrowdCount Information")
                .bold()
                .foregroundColor(.primary)
            Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                .font(.body)
            Spacer()
            Text("Thank you very much for using the CrowdCount App.")
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("If you want to know more about us, please refer to our website above. If you have any issues, questions or want to leave a review feel free to send us an email and we'll be happy to hear from you.")
                .padding(.bottom,5)
                .padding(.horizontal)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Spacer()
            
            Image(systemName: "hand.raised.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundColor(.blue)
            Text("Your privacy is important to us.")
                .padding(.top,5)
                .foregroundColor(.primary)
                .bold()
            Text("Visit our \(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)")) to see how we manage your data.")
                .foregroundColor(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
            Spacer()
            Image(systemName: "leaf.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundColor(.green)
            Text("Dedicated to remaining carbon neutral.")
                .foregroundColor(.primary)
                .padding(.top,5)
                .bold()
             Text("Visit our website to see how.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundColor(.yellow)
            Text("Want to support us?")
                .foregroundColor(.primary)
                .padding(.top,5)
                .bold()
             Text("Thank you! We appreciate anything.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button(action: {
                    if let url = URL(string: "https://www.venmo.com/u/crowdcount") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("Venmo")
                            .foregroundColor(.primary)
                        Image(systemName: "arrow.up.right")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundColor(.primary)
                            .offset(x:-2,y:1)
                    }
                }
            }
            .offset(y:-5)
            
            Spacer()
            Text("CrowdCount App version \(appVersion ?? "error") (\(appBuildNumber ?? "error"))")
                .foregroundColor(.secondary)
            Spacer()
            Text("\u{00A9} 2025 CrowdCount. All rights reserved.")
                .foregroundColor(.secondary)
                .font(.caption2)
                .padding(2)
            Text("\(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)")) | \(Text("[Terms of Use](https://www.crowdcount.tech/legal/terms-of-use)"))")
                .foregroundColor(.secondary)
                .tint(.secondary)
                .font(.caption2)

        }
        .navigationBarTitle("Information", displayMode: .inline)
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
    }
}

struct InformationView_Previews: PreviewProvider {
    static var previews: some View {
        InformationView()
            .environmentObject(AppSettings())
    }
}
