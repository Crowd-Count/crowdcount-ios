import SwiftUI

@MainActor
class AlertViewModel: ObservableObject {
    @Published var showAlert: Bool = false
    @Published var alertExists: Bool = false
    @Published var alertInfo: (type: String, title: String, body: String, alert_id: String) = ("", "", "", "")
    @Published var isLoading: Bool = false

    private let apiService = APIService.shared

    func checkForAlert() {
        Task {
            await checkForAlertAsync()
        }
    }

    func checkForAlertAsync() async {
        isLoading = true

        do {
            let hasAlert = try await apiService.checkForAlert()

            if hasAlert {
                await fetchAlertInfoAsync()
            } else {
                print("No alert present")
                self.isLoading = false
                self.alertExists = false
            }
        } catch {
            print("Error fetching alert status: \(error)")
            self.isLoading = false
        }
    }

    func fetchAlertInfo() {
        Task {
            await fetchAlertInfoAsync()
        }
    }

    func fetchAlertInfoAsync() async {
        do {
            if let alert = try await apiService.fetchAlertInfo() {
                print("Fetched alert - Type: \(alert.type), Title: \(alert.title), Body: \(alert.body), ID: \(alert.alertId)")
                self.alertInfo = (type: alert.type, title: alert.title, body: alert.body, alert_id: alert.alertId)
                self.alertExists = true

                if !self.hasSeenAlert(alert_id: alert.alertId) {
                    self.showAlert = true
                    self.markAlertAsSeen(alert_id: alert.alertId)
                }
            } else {
                print("Error parsing alert_info JSON structure")
            }
            self.isLoading = false
        } catch {
            print("Error fetching alert info: \(error)")
            self.isLoading = false
        }
    }

    func hasSeenAlert(alert_id: String) -> Bool {
        let seen = UserDefaults.standard.bool(forKey: "hasSeenAlert_\(alert_id)")
        print("Checking if alert \(alert_id) has been seen: \(seen)")
        return seen
    }

    func markAlertAsSeen(alert_id: String) {
        UserDefaults.standard.set(true, forKey: "hasSeenAlert_\(alert_id)")
        print("Marked as seen: \(alert_id)")
    }
}

struct AlertOverlay: View {
    @ObservedObject var alertViewModel: AlertViewModel
    @EnvironmentObject var appSettings: AppSettings
    
    var body: some View {
        VStack {
        }
        .sheet(isPresented: $alertViewModel.showAlert) {
            AlertPage(alertInfo: alertViewModel.alertInfo) {
                print("AlertPage dismissed")
                alertViewModel.markAlertAsSeen(alert_id: alertViewModel.alertInfo.alert_id)
                alertViewModel.showAlert = false
            }
            .environmentObject(appSettings)
        }
        .onAppear {
            print("AlertOverlay onAppear")
            alertViewModel.checkForAlert()
        }
    }
}

struct AlertPage: View {
    let alertInfo: (type: String, title: String, body: String, alert_id: String)
    let dismissAction: () -> Void
    
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Image(systemName: "chevron.compact.down")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary.opacity(0.5))
                        .offset(y: -50)
                        .frame(width: 40, height: 10)
                    Spacer()
                    switch alertInfo.type {
                    case "info":
                        Image(systemName: "info.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .blue)
                            .frame(width: 50, height: 50)
                    case "warning":
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .yellow)
                            .frame(width: 50, height: 50)
                    case "celebration":
                        Image(systemName: "sparkles")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.yellow)
                            .frame(width: 50, height: 50)
                    case "privacy":
                        Image(systemName: "hand.raised.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.blue)
                            .frame(width: 50, height: 50)
                    case "terms-of-use":
                        Image(systemName: "book.closed.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.orange)
                            .frame(width: 50, height: 50)
                    case "leaf":
                        Image(systemName: "leaf.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.green)
                            .frame(width: 50, height: 50)
                    default:
                        Image(systemName: "info.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .blue)
                            .frame(width: 50, height: 50)
                    }
                    Text(alertInfo.title)
                        .font(.title)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.top)
                    Text(alertInfo.body)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(5)
                        .multilineTextAlignment(.center)
                    Spacer()
                    Text("Swipe down or close to dismiss.")
                        .italic()
                        .padding()
                        .foregroundColor(.secondary)
                    switch alertInfo.type {
                    case "info":
                        Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    case "warning":
                        Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[help@crowdcount.tech](mailto:help@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    case "celebration":
                        Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    case "privacy":
                        Text("\(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    case "terms-of-use":
                        Text("\(Text("[Terms of Use](https://www.crowdcount.tech/legal/terms-of-use)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    case "leaf":
                        Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    default:
                        Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))  |  \(Text("[info@crowdcount.tech](mailto:info@crowdcount.tech)"))")
                            .font(.body)
                            .tint(.blue)
                    }
                }
                .padding()
            }
            .navigationBarItems(trailing: Button(action: {
                print("Close button tapped")
                dismissAction()
            }) {
                Text("Close")
                    .foregroundColor(.blue)
                    .bold()
            })
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }
}
