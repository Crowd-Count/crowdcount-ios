import SwiftUI
import Combine
import Foundation
import UIKit

// Data Model for the API Response
struct AvailableDatesResponse: Decodable {
    let dates: [String]
}

// Define a data model to store the day's data
struct DayDataResponse: Decodable {
    let day_data: [String: Double]
}

// Define a data model to store the average day's data
struct AverageDayDataResponse: Decodable {
    let average_day_data: [String: Double]
}

// Define a data model to store the week's data
struct WeekDataResponse: Decodable {
    let week_data: [String: Double]
}

// Define a data model to store the average week's data
struct AverageWeekDataResponse: Decodable {
    let average_week_data: [String: Double]
}

// NEW: Define data models for year data
struct YearDataResponse: Decodable {
    let year_data: [String: Double]
}

struct AverageYearDataResponse: Decodable {
    let average_year_data: AverageYearDataValue
}

// NEW: Handle both dictionary and "N/A" string responses
enum AverageYearDataValue: Decodable {
    case data([String: Double])
    case notAvailable(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let dataDict = try? container.decode([String: Double].self) {
            self = .data(dataDict)
        } else if let naString = try? container.decode(String.self) {
            self = .notAvailable(naString)
        } else {
            throw DecodingError.typeMismatch(AverageYearDataValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected dictionary or string"))
        }
    }
}

struct ConnectionStatusResponse: Decodable {
    let status: String
}

struct WeekInfo: Identifiable {
    var id = UUID()
    var label: String
    var startDate: String
}

struct CSVData: Identifiable {
    var id = UUID()
    var time: String
    var count: Int
}

struct HistoricView: View {
    let userId: String
    let userUUID: UUID
    @Binding var userPasswords: [UUID: String]
    @State private var selectedDay: String = "Today"
    @State private var selectedWeek: WeekInfo? = nil
    @State private var selectedYear: String = "This Year"
    @State private var availableDates: [String] = []
    @State private var availableWeeks: [WeekInfo] = []
    @State private var availableYears: [String] = []
    @State private var dayData: [String: Double] = [:]
    @State private var averageDayData: [String: Double]?
    @State private var weekData: [String: Double] = [:]
    @State private var averageWeekData: [String: Double]?
    @State private var yearData: [String: Double] = [:] // NEW
    @State private var averageYearData: [String: Double]? // NEW
    @State private var hasInsufficientYearData: Bool = false // NEW
    @State private var isDeviceOnline: Bool = false
    @State private var hasDataForSelectedDay: Bool = true
    @State private var hasDataForSelectedWeek: Bool = true
    @State private var hasDataForSelectedYear: Bool = true // NEW
    @State private var mostRecentDataTime: String? = nil
    @State private var mostRecentWeekDay: String? = nil
    
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                // Day view with chart and download button
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableDates.sorted(by: >), id: \.self) { date in
                                let displayDate = (date == getCurrentDate()) ? "Today" : formattedDatelong(from: date)
                                Button(displayDate, action: {
                                    selectedDay = displayDate
                                    checkAndFetchDayData(for: date)
                                    if date == getCurrentDate() {
                                        fetchConnectionStatus()
                                    }
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedDay)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()

                        Button(action: {
                            checkAndDownloadData(for: selectedDay, period: "day")
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .offset(y: -3)
                        }
                        .padding()
                    }

                    if hasDataForSelectedDay {
                        BarGraphDay(
                            dayData: dayData,
                            averageDayData: averageDayData,
                            isTodayView: selectedDay == "Today",
                            selectedDate: selectedDay,
                            isDeviceOnline: isDeviceOnline,
                            mostRecentDataTime: mostRecentDataTime
                        )
                            .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for today")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another day")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(25)
                .padding(.horizontal)
                .id("dayView")

                // Weekly chart view with download button
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableWeeks) { week in
                                Button(week.label, action: {
                                    selectedWeek = week
                                    checkAndFetchWeekData(for: week.startDate)
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedWeek?.label ?? "Select Week")
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    if hasDataForSelectedWeek {
                        BarGraphWeek(
                            weekData: weekData,
                            averageWeekData: averageWeekData ?? [:],
                            selectedDate: selectedWeek?.label ?? ""
                        )
                            .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for this week")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another week")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(30)
                .padding(.horizontal)
                .id("weekView")

                // UPDATED: Yearly chart view with actual functionality
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableYears, id: \.self) { year in
                                let displayYear = (year == getCurrentYear()) ? "This Year" : year
                                Button(displayYear, action: {
                                    selectedYear = displayYear
                                    let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                                    fetchYearData(for: yearInt)
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedYear)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    if hasDataForSelectedYear {
                        BarGraphYear(
                            yearData: yearData,
                            averageYearData: averageYearData,
                            selectedYear: selectedYear,
                            hasInsufficientData: hasInsufficientYearData
                        )
                        .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for this year")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another year")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(30)
                .padding(.horizontal)
                .id("yearView")

                VStack {
                    Text("Issues with this page?")
                        .bold()
                        .foregroundColor(.primary)
                        .padding(10)
                    Text("We're still working on this, so feel free to report anything by sending us a message!")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("help@crowdcount.tech")
                        .font(.body)
                        .padding()
                        .onTapGesture {
                            if let url = URL(string: "mailto:help@crowdcount.tech") {
                                UIApplication.shared.open(url)
                            }
                        }

                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(30)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
        .navigationBarTitle("Count History", displayMode: .inline)
        .onAppear {
            fetchAvailableDates()
            checkAndFetchDayData(for: getCurrentDate())
            fetchConnectionStatus()
            // NEW: Fetch current year data on appear
            fetchYearData(for: getCurrentYearInt())
        }
    }

    private func viewContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
            content()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                .padding(.bottom)
        }
        .padding()
    }

    func fetchAvailableDates() {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        var urlComponents = URLComponents(string: "\(AppSettings.apiBaseURL)/get_user_days")!
        urlComponents.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "password", value: password)
        ]

        guard let url = urlComponents.url else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to fetch available dates: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            if let rawString = String(data: data, encoding: .utf8) {
                print("Raw response data: \(rawString)")
            }

            do {
                let decodedResponse = try JSONDecoder().decode(AvailableDatesResponse.self, from: data)
                DispatchQueue.main.async {
                    self.availableDates = decodedResponse.dates.sorted(by: >)
                    self.availableYears = Array(Set(decodedResponse.dates.map { formattedYear(from: $0) })).sorted(by: >)
                    self.availableWeeks = generateAvailableWeeks(from: decodedResponse.dates)
                    if let firstWeek = self.availableWeeks.first {
                        self.selectedWeek = firstWeek
                        self.checkAndFetchWeekData(for: firstWeek.startDate)
                    }
                }
            } catch {
                print("Failed to decode available dates: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
            }
        }.resume()
    }

    // NEW: Function to fetch year data
    func fetchYearData(for year: Int) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let urlString = "\(AppSettings.apiBaseURL)/get_year_data?user_id=\(userId)&password=\(password)&year=\(year)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch year data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.hasDataForSelectedYear = false
                }
                return
            }

            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.hasDataForSelectedYear = false
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(YearDataResponse.self, from: data)
                DispatchQueue.main.async {
                    self.yearData = decodedResponse.year_data
                    self.hasDataForSelectedYear = !decodedResponse.year_data.isEmpty
                    print("Parsed yearData: \(self.yearData)")
                }
                
                // Fetch average year data
                self.fetchAverageYearData(for: year, password: password)
            } catch {
                print("Failed to decode year data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
                DispatchQueue.main.async {
                    self.hasDataForSelectedYear = false
                }
            }
        }.resume()
    }

    // NEW: Function to fetch average year data
    func fetchAverageYearData(for year: Int, password: String) {
        let urlString = "\(AppSettings.apiBaseURL)/get_average_year_data?user_id=\(userId)&password=\(password)&year=\(year)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch average year data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.averageYearData = nil
                    self.hasInsufficientYearData = true
                }
                return
            }

            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.averageYearData = nil
                    self.hasInsufficientYearData = true
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(AverageYearDataResponse.self, from: data)
                DispatchQueue.main.async {
                    switch decodedResponse.average_year_data {
                    case .data(let yearDict):
                        self.averageYearData = yearDict
                        self.hasInsufficientYearData = false
                        print("Parsed averageYearData: \(yearDict)")
                    case .notAvailable(let message):
                        self.averageYearData = nil
                        self.hasInsufficientYearData = true
                        print("Insufficient year data: \(message)")
                    }
                }
            } catch {
                print("Failed to decode average year data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
                DispatchQueue.main.async {
                    self.averageYearData = nil
                    self.hasInsufficientYearData = true
                }
            }
        }.resume()
    }

    func checkAndFetchDayData(for date: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let formattedDate = (date == "Today") ? getCurrentDate() : formattedDateshort(from: date)
        let urlString = "\(AppSettings.apiBaseURL)/check_if_user_has_day?user_id=\(userId)&password=\(password)&date=\(formattedDate)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to check data availability: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let hasDay = jsonResponse["has_day"] as? Bool {
                    DispatchQueue.main.async {
                        self.hasDataForSelectedDay = hasDay
                        if hasDay {
                            self.fetchDayData(for: formattedDate)
                        } else {
                            self.dayData = [:]
                            self.averageDayData = nil
                            self.mostRecentDataTime = nil
                        }
                    }
                } else {
                    print("Failed to parse JSON response")
                }
            } catch {
                print("Failed to parse response: \(error.localizedDescription)")
            }
        }.resume()
    }

    // Fetch a single UTC day’s data, then rotate hour bins into the user’s local time
    func fetchDayData(for date: String) {
        // `date` must be a UTC "yyyy-MM-dd" string sent to your API
        guard let password = userPasswords[userUUID] else {
            print("fetchDayData: missing password for user \(userUUID)")
            return
        }

        let urlString = "\(AppSettings.apiBaseURL)/get_day_data?user_id=\(userId)&password=\(password)&date=\(date)"
        guard let url = URL(string: urlString) else {
            print("fetchDayData: bad URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("fetchDayData: network error:", error.localizedDescription)
                DispatchQueue.main.async {
                    self.dayData = [:]
                    self.mostRecentDataTime = nil
                }
                return
            }
            guard let data = data else {
                print("fetchDayData: empty response data")
                DispatchQueue.main.async {
                    self.dayData = [:]
                    self.mostRecentDataTime = nil
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(DayDataResponse.self, from: data)
                DispatchQueue.main.async {
                    // Shift 0..23 UTC hour keys into local hour keys for that calendar date
                    let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: date, bins: decoded.day_data)
                    self.dayData = localBins
                    self.mostRecentDataTime = self.findMostRecentDataTime(in: localBins)
                }
            } catch {
                print("fetchDayData: decode error:", error)
                if let raw = String(data: data, encoding: .utf8) { print("raw:", raw) }
                DispatchQueue.main.async {
                    self.dayData = [:]
                    self.mostRecentDataTime = nil
                }
            }
        }.resume()

        // Also load the average for this UTC date
        fetchAverageDayData(for: date, password: password)
    }


    func findMostRecentDataTime(in data: [String: Double]) -> String? {
        let nonZeroEntries = data.filter { $0.value > 0 }
        guard !nonZeroEntries.isEmpty else { return nil }
        
        let hourNumbers = nonZeroEntries.keys.compactMap { Int($0) }
        guard let latestHour = hourNumbers.max() else { return nil }
        
        return String(latestHour)
    }

    func findMostRecentWeekDay(in data: [String: Double]) -> String? {
        let nonZeroEntries = data.filter { $0.value > 0 }
        guard !nonZeroEntries.isEmpty else { return nil }
        
        let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        
        for day in dayOrder.reversed() {
            if nonZeroEntries.keys.contains(day) {
                return day
            }
        }
        
        return nonZeroEntries.keys.first
    }

    // Fetch average day bins for the UTC date, then rotate hour bins into local time
    func fetchAverageDayData(for date: String, password: String) {
        let urlString = "\(AppSettings.apiBaseURL)/get_average_day_data?user_id=\(userId)&password=\(password)&date=\(date)"
        guard let url = URL(string: urlString) else {
            print("fetchAverageDayData: bad URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("fetchAverageDayData: network error:", error.localizedDescription)
                DispatchQueue.main.async { self.averageDayData = nil }
                return
            }
            guard let data = data else {
                print("fetchAverageDayData: empty response data")
                DispatchQueue.main.async { self.averageDayData = nil }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(AverageDayDataResponse.self, from: data)
                let serverBins = decoded.average_day_data
                let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: date, bins: serverBins)

                DispatchQueue.main.async {
                    self.averageDayData = localBins.isEmpty ? nil : localBins
                }
            } catch {
                print("fetchAverageDayData: decode error:", error)
                if let raw = String(data: data, encoding: .utf8) { print("raw:", raw) }
                DispatchQueue.main.async { self.averageDayData = nil }
            }
        }.resume()
    }


    func checkAndFetchWeekData(for startDate: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = formattedDateshort(from: startDate)
        }

        print("Formatted Start Date for week data check: \(formattedStartDate)")

        let urlString = "\(AppSettings.apiBaseURL)/check_if_user_has_week?user_id=\(userId)&password=\(password)&date=\(formattedStartDate)"
        
        print("URL String: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to check data availability: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let hasWeek = jsonResponse["has_week"] as? Bool {
                    print("Has Week: \(hasWeek)")
                    DispatchQueue.main.async {
                        self.hasDataForSelectedWeek = hasWeek
                        if hasWeek {
                            self.fetchWeekData(for: formattedStartDate)
                        } else {
                            self.weekData = [:]
                            self.averageWeekData = nil
                            self.mostRecentWeekDay = nil
                        }
                    }
                } else {
                    print("Failed to parse JSON response")
                }
            } catch {
                print("Failed to parse response: \(error.localizedDescription)")
            }
        }.resume()
    }

    func getCurrentWeekStartDate() -> String {
        let calendar = Calendar.current
        let currentDate = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: startOfWeek)
    }

    func fetchWeekData(for date: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let urlString = "\(AppSettings.apiBaseURL)/get_week_data?user_id=\(userId)&password=\(password)&date=\(date)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch week data: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(WeekDataResponse.self, from: data)
                DispatchQueue.main.async {
                    self.weekData = decodedResponse.week_data
                    self.mostRecentWeekDay = self.findMostRecentWeekDay(in: decodedResponse.week_data)
                    print("Parsed weekData: \(self.weekData)")
                    print("Most recent week day: \(String(describing: self.mostRecentWeekDay))")
                }
            } catch {
                print("Failed to decode week data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
            }
        }.resume()

        fetchAverageWeekData(for: date, password: password)
    }

    func fetchAverageWeekData(for date: String, password: String) {
        let urlString = "\(AppSettings.apiBaseURL)/get_average_week_data?user_id=\(userId)&password=\(password)&date=\(date)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch average week data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
                return
            }

            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(AverageWeekDataResponse.self, from: data)
                DispatchQueue.main.async {
                    self.averageWeekData = decodedResponse.average_week_data
                    print("Parsed averageWeekData: \(String(describing: self.averageWeekData))")
                }
            } catch {
                print("Failed to decode average week data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
            }
        }.resume()
    }

    func fetchConnectionStatus() {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/connection_status?user_id=\(userId)") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch connection status: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(ConnectionStatusResponse.self, from: data)
                DispatchQueue.main.async {
                    self.isDeviceOnline = decodedResponse.status == "online"
                }
            } catch {
                print("Failed to decode connection status: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
            }
        }.resume()
    }

    // Display: server gives "yyyy-MM-dd" in UTC → show as local long date
    func formattedDatelong(from date: String) -> String {
        TZ.longLocal(fromUTCyyyyMMdd: date)
    }

    // Build API param: long local label → "yyyy-MM-dd" **in UTC**
    func formattedDateshort(from longDate: String) -> String {
        let fIn = DateFormatter()
        fIn.timeZone = .current
        fIn.locale   = .current
        fIn.dateStyle = .long
        guard let d = fIn.date(from: longDate) else { return longDate }
        return TZ.yyyyMMddUTC(from: d)
    }

    // Year extraction from UTC date string
    func formattedYear(from date: String) -> String {
        guard let d = TZ.utcDate(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "yyyy"
        return f.string(from: d)
    }

    // NEW: Helper functions for year handling
    func getCurrentYear() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"
        return dateFormatter.string(from: Date())
    }

    func getCurrentYearInt() -> Int {
        return Calendar.current.component(.year, from: Date())
    }

    func compareMonths(_ lhs: String, _ rhs: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        if let lhsDate = dateFormatter.date(from: lhs), let rhsDate = dateFormatter.date(from: rhs) {
            return lhsDate > rhsDate
        }
        return lhs > rhs
    }

    func generateAvailableWeeks(from dates: [String]) -> [WeekInfo] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TZ.utc
        let sortedDates = dates.compactMap { f.date(from: $0) }.sorted(by: >)

        var weeks = [WeekInfo]()
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        var currentWeekStart: Date?
        var currentWeekLabel = "This Week"
        var currentWeekDates = [Date]()

        for date in sortedDates {
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            if currentWeekStart == nil {
                currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
                currentWeekLabel = "This Week"
            }

            if calendar.component(.weekOfYear, from: currentWeekStart!) == weekOfYear {
                currentWeekDates.append(date)
            } else {
                if let startDate = currentWeekStart {
                    weeks.append(WeekInfo(label: currentWeekLabel, startDate: f.string(from: startDate)))
                }
                currentWeekDates.removeAll()
                currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
                currentWeekDates.append(date)
                currentWeekLabel = formattedWeek(from: currentWeekStart!)
            }
        }

        if let startDate = currentWeekStart, !currentWeekDates.isEmpty {
            weeks.append(WeekInfo(label: currentWeekLabel, startDate: f.string(from: startDate)))
        }

        return weeks
    }

    func formattedWeek(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd"
        let startOfWeek = dateFormatter.string(from: date)
        let endOfWeek = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: date)!)
        return "\(startOfWeek) - \(endOfWeek)"
    }

    // API "today": use today's **UTC** yyyy-MM-dd
    func getCurrentDate() -> String {
        TZ.yyyyMMddUTC(from: Date())
    }

    func checkAndDownloadData(for date: String, period: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let formattedDate = (date == "Today") ? getCurrentDate() : formattedDateshort(from: date)

        let urlString = "\(AppSettings.apiBaseURL)/check_if_user_has_day?user_id=\(userId)&password=\(password)&date=\(formattedDate)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to check data availability: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("Raw JSON response: \(jsonResponse)")

                    if let hasData = jsonResponse["has_day"] as? Bool {
                        if hasData {
                            self.downloadData(for: formattedDate, period: period, password: password)
                        } else {
                            print("No data available for the selected date.")
                        }
                    } else {
                        print("Key 'has_data' not found in the response.")
                    }
                } else {
                    print("Failed to parse JSON response")
                }
            } catch {
                print("Failed to parse response: \(error.localizedDescription)")
            }
        }.resume()
    }

    func downloadData(for date: String, period: String, password: String) {
        let urlString: String
        switch period {
        case "day":
            urlString = "\(AppSettings.apiBaseURL)/export_csv?user_id=\(userId)&password=\(password)&date=\(date)"
        case "week":
            urlString = "\(AppSettings.apiBaseURL)/export_csv?user_id=\(userId)&password=\(password)&date=\(date)"
        case "year":
            print("Year data export is not yet implemented")
            return
        default:
            return
        }

        guard let url = URL(string: urlString) else { return }

        let downloadTask = URLSession.shared.downloadTask(with: url) { tempLocalUrl, response, error in
            if let error = error {
                print("Failed to download data: \(error.localizedDescription)")
                return
            }

            guard let tempLocalUrl = tempLocalUrl else {
                print("No URL for downloaded file")
                return
            }

            DispatchQueue.main.async {
                do {
                    let fileData = try Data(contentsOf: tempLocalUrl)
                    let fileName = "user_\(self.userId)_data_\(date).csv"

                    if let topController = UIApplication.shared.topViewController() {
                        presentShareSheet(data: fileData, fileName: fileName, from: topController)
                    }
                } catch {
                    print("Failed to read downloaded file: \(error.localizedDescription)")
                }
            }
        }
        downloadTask.resume()
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return UIApplication.shared.topViewController() ?? UIViewController()
    }
}

extension UIApplication {
    func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .filter({ $0.activationState == .foregroundActive })
        .map({ $0 as? UIWindowScene })
        .compactMap({ $0 })
        .first?.windows
        .filter({ $0.isKeyWindow }).first?.rootViewController) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

// MARK: - Time zone & bin-shifting helpers
private enum TZ {
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func utcDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    static func yyyyMMddUTC(from localDate: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: localDate)
    }

    static func longLocal(fromUTCyyyyMMdd s: String) -> String {
        guard let d = utcDate(from: s) else { return s }
        let f = DateFormatter()
        f.timeZone = .current
        f.locale = .current
        f.dateStyle = .long
        return f.string(from: d)
    }

    // Shift 0..23 UTC hourly bins into local 0..23 bins for the *same calendar slot*.
    // (Counts that would spill across day edges are rotated; server-side re-aggregation
    // would be needed for perfect day-boundary semantics.)
    static func shiftHourlyBinsUTCtoLocal(forUTCDate yyyyMMdd: String,
                                          bins: [String: Double]) -> [String: Double] {
        guard let d = utcDate(from: yyyyMMdd) else { return bins }
        let offsetHours = TimeZone.current.secondsFromGMT(for: d) / 3600  // DST-aware
        var out: [String: Double] = [:]
        for (k, v) in bins {
            guard let h = Int(k) else { continue }
            var localH = (h + offsetHours) % 24
            if localH < 0 { localH += 24 }
            out[String(localH), default: 0] += v
        }
        return out
    }
}
