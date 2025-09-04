import SwiftUI

struct ReportContentView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var selectedOption: String = ""
    @State private var selectedReport: String = ""
    @State private var otherReportContent: String = ""
    @State private var options: [String] = []
    @State private var reportOptions: [String] = [
        "This location is falsifying its count data",
        "This location's counter is malfunctioning",
        "This location has moved or no longer exists",
        "Other"
    ]
    @State private var isLoading: Bool = true
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showSuccess: Bool = false
    @State private var showCheckmark: Bool = false
    
    @EnvironmentObject var appSettings: AppSettings

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            if showSuccess {
                VStack {
                    Image(systemName: "checkmark.square.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.primary)
                        .symbolRenderingMode(.hierarchical)
                        .transition(.scale)
                    Text("Report Submitted!")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding()
                    Text("Thank you, we'll go take a look at it.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
//                    Image(systemName: "exclamationmark.bubble.fill")
//                        .resizable()
//                        .scaledToFit()
//                        .frame(width: 50, height: 50)
//                        .foregroundColor(.red)
//                        .padding(5)
                
                Form {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Loading options...")
                            Spacer()
                        }
                    } else {
                        Section(header: Text("Your Information")) {
                            TextField("Name", text: $name)
                                .autocapitalization(.words)
                                .padding()
                                .background(Color.secondary.opacity(0.25))
                                .cornerRadius(15)
                            TextField("Email", text: $email)
                                .keyboardType(.emailAddress)
                                .padding()
                                .background(Color.secondary.opacity(0.25))
                                .cornerRadius(15)
                        }
                        
                        Section(header: Text("Select a Location")) {
                            Picker("Available Locations:", selection: $selectedOption) {
                                ForEach(options, id: \.self) { option in
                                    Text(option)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        Section(header: Text("What is wrong?")) {
                            List(reportOptions, id: \.self) { option in
                                Button(action: {
                                    selectedReport = option
                                    if option != "Other" {
                                        otherReportContent = ""
                                    }
                                }) {
                                    HStack {
                                        Text(option)
                                        Spacer()
                                        if selectedReport == option {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                            
                            if selectedReport == "Other" {
                                TextField("Please specify", text: $otherReportContent)
                                    .padding()
                                    .background(Color.secondary.opacity(0.25))
                                    .cornerRadius(15)
                            }
                        }
                        
                        Section {
                            Button(action: {
                                submitReport()
                            }) {
                                Text("Submit Report")
                            }
                            .disabled(selectedReport.isEmpty || selectedOption.isEmpty || name.isEmpty || email.isEmpty || (selectedReport == "Other" && otherReportContent.isEmpty))
                        }
                    }
                }
                
                Link("Click to see how we manage reports", destination: URL(string: "https://www.crowdcount.tech/report/info")!)
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(5)
                    .italic()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Submit a Report")
                    .font(.headline)
            }
        }
        .onAppear(perform: fetchOptions)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Report Submission"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func submitReport() {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/submit_report") else {
            alertMessage = "Invalid URL"
            showAlert = true
            return
        }
        
        let reportContent = selectedReport == "Other" ? otherReportContent : selectedReport
        
        var reportData: [String: Any] = [
            "name": name,
            "email": email,
            "location": selectedOption,
            "content": reportContent
        ]
        
        if selectedReport == "Other" {
            reportData["other"] = otherReportContent
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: reportData)
        } catch {
            alertMessage = "Failed to encode report data"
            showAlert = true
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    alertMessage = "Error submitting report: \(error.localizedDescription)"
                    showAlert = true
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    alertMessage = "No data received from server"
                    showAlert = true
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    withAnimation {
                        showSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } else {
                let responseMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                DispatchQueue.main.async {
                    alertMessage = "Failed to submit report: \(responseMessage)"
                    showAlert = true
                }
            }
        }.resume()
    }
    
    private func fetchOptions() {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_all_location_names") else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                if let decodedResponse = try? JSONDecoder().decode(LocationNamesResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.options = decodedResponse.location_names.sorted()
                        self.isLoading = false
                    }
                } else {
                    print("Failed to decode response")
                }
            } else if let error = error {
                print("Error fetching options: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct LocationNamesResponse: Codable {
    let location_names: [String]
}

struct ReportContentView_Previews: PreviewProvider {
    static var previews: some View {
        ReportContentView()
    }
}
