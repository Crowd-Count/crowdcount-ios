import SwiftUI

struct BarGraphDay: View {
    var dayData: [String: Double]
    var averageDayData: [String: Double]?
    var isTodayView: Bool
    var selectedDate: String
    var isDeviceOnline: Bool
    var mostRecentDataTime: String?

    // POS overlay
    var posHourlyData: [String: POSTransactionData.POSHourlyEntry]? = nil
    var showPOSOverlay: Bool = false

    private let allHours = (0..<24).map { String($0) }

    // Live data highlight (commented out — POS transactions line uses green now)
//    private var isLiveData: Bool {
//        guard isTodayView && isDeviceOnline else { return false }
//        guard let mostRecentDataTime = mostRecentDataTime,
//              let mostRecentHour = Int(mostRecentDataTime) else { return false }
//        let currentHour = Calendar.current.component(.hour, from: Date())
//        return mostRecentHour == currentHour
//    }
//
//    private var highlightIndex: Int? {
//        guard isLiveData, let h = mostRecentDataTime, let hour = Int(h) else { return nil }
//        return hour
//    }

    /// Convert POS hourly data to [String: Int] for the chart wrapper
    private var posTransactionCounts: [String: Int]? {
        guard let pos = posHourlyData else { return nil }
        var result: [String: Int] = [:]
        for (hour, entry) in pos {
            result[hour] = entry.transactions
        }
        return result
    }

    var body: some View {
        VStack {
            CombinedChartUIView(
                barData: dayData,
                averageData: averageDayData,
                labels: allHours,
                posData: posTransactionCounts,
                showPOS: showPOSOverlay
            )
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewDay(
                selectedDate: selectedDate,
                showAverage: averageDayData != nil,
                showPOS: showPOSOverlay
            )
            .padding(.top, 20)
        }
        .padding([.top, .bottom])
    }
}

struct YAxisOffsetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .offset(x: -5)
    }
}

struct LegendViewDay: View {
    var selectedDate: String
    var showAverage: Bool
    var showPOS: Bool = false
    @State private var showAlert = false

    var body: some View {
        FlowLayout(spacing: 6) {
            legendItem(color: .blue, text: stripYear(selectedDate))

            Button(action: { self.showAlert = true }) {
                legendItem(color: .orange, text: "Daily Average", showInfo: true)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Daily Average"),
                      message: Text("The average is calculated based on data from the same weekday over the previous 8 weeks, provided there is enough data. A minimum of 2 weeks of data is required.\n\nIf there isn't sufficient data, the average will not be displayed on the graph."),
                      dismissButton: .default(Text("OK")))
            }

            // Live data legend (commented out — POS transactions line uses green now)
//            if isLiveData {
//                Button(action: { self.showLiveAlert = true }) {
//                    legendItem(color: .green, text: "Live Data", showInfo: true)
//                }
//                .alert(isPresented: $showLiveAlert) {
//                    Alert(title: Text("Info for Live Data"),
//                          message: Text("The Live Data shows real-time data for the current hour. This updates automatically every 30 seconds to reflect the latest count."),
//                          dismissButton: .default(Text("OK")))
//                }
//            }

            if showPOS {
                legendItem(color: .green, text: "Transactions", isDashed: true)
            }
        }
        .padding(.horizontal)
    }

    private func stripYear(_ text: String) -> String {
        if let range = text.range(of: #",\s*\d{4}$"#, options: .regularExpression) {
            return String(text[text.startIndex..<range.lowerBound])
        }
        return text
    }

    private func legendItem(color: Color, text: String, showInfo: Bool = false, isDashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isDashed {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 14, height: 3)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            if showInfo {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct BarGraph_Previews: PreviewProvider {
    static var previews: some View {
        BarGraphDay(
            dayData: ["6": 12.8, "7": 15.0, "8": 18.0, "9": 17.6, "10": 16.1, "11": 12.4, "12": 15.3, "13": 16.9],
            averageDayData: ["6": 10.0, "7": 12.0, "8": 15.0, "9": 14.0, "10": 13.0, "11": 11.0, "12": 13.5, "13": 14.0],
            isTodayView: true,
            selectedDate: "July 9, 2024",
            isDeviceOnline: true,
            mostRecentDataTime: "13"
        )
        .frame(height: 300)
    }
}
