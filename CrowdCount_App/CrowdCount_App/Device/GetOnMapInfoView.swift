import SwiftUI

struct GetOnMapInfoView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
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

                Text("To create an ad for your business, your counter needs to be visible on the CrowdCount map first.")
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

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
                            Text("Once approved, your counter will appear on the map and you can create ads!")
                                .foregroundColor(.primary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

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
                .padding(.top, 10)

                Spacer()
            }
            .padding()
        }
        .navigationBarTitle("Get on the Map", displayMode: .inline)
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
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
