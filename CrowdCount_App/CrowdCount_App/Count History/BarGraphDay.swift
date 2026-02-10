import SwiftUI
import Charts

struct BarGraphDay: View {
    var dayData: [String: Double]
    var averageDayData: [String: Double]?
    var isTodayView: Bool
    var selectedDate: String
    var isDeviceOnline: Bool
    var mostRecentDataTime: String? // Most recent hour with data

    private let allHours = (0..<24).map { String($0) }

    // Computed property to check if we have truly live data (current hour matches most recent data hour)
    private var isLiveData: Bool {
        guard isTodayView && isDeviceOnline else { return false }
        guard let mostRecentDataTime = mostRecentDataTime,
              let mostRecentHour = Int(mostRecentDataTime) else { return false }
        let currentHour = Calendar.current.component(.hour, from: Date())
        return mostRecentHour == currentHour
    }

    var body: some View {
        VStack {
            Chart {
                barMarks()
                averageBarMarks()
            }
            .chartXScale(domain: allHours)
            .chartXAxis {
                AxisMarks(values: stride(from: 0, through: 23, by: 2).map { String($0) }) { value in
                    if let strValue = value.as(String.self) {
                        AxisValueLabel {
                            Text(strValue)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { value in
                    AxisValueLabel {
                        Text(value.as(Int.self)?.description ?? "")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .modifier(YAxisOffsetModifier()) // Apply the custom view modifier
                    }
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.5))
                }
            }
            .chartYScale(domain: 0...(max(1, dayData.values.map { max(0, $0) }.max() ?? 1, averageDayData?.values.map { max(0, $0) }.max() ?? 1)))
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewDay(selectedDate: selectedDate, isTodayView: isTodayView, isDeviceOnline: isDeviceOnline, showAverage: averageDayData != nil, isLiveData: isLiveData)
                .padding(.top, 20) // Adjust padding for more space between graph and legend
        }
        .padding([.top, .bottom]) // Add padding to top and bottom of the view
    }

    @ChartContentBuilder
    private func barMarks() -> some ChartContent {
        ForEach(Array(allHours.enumerated()), id: \.element) { index, hour in
            if let count = dayData[hour] {
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Count", max(0, count))
                )
                .foregroundStyle(shouldHighlightBar(for: hour) ? .green : .blue)
                .opacity(shouldHighlightBar(for: hour) ? 1.0 : (index % 2 == 0 ? 1.0 : 0.85))
                .cornerRadius(2)
                .position(by: .value("Series", "Data"))
            }
        }
    }

    @ChartContentBuilder
    private func averageBarMarks() -> some ChartContent {
        if let averageDayData = averageDayData {
            ForEach(Array(allHours.enumerated()), id: \.element) { index, hour in
                if let averageCount = averageDayData[hour] {
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Count", max(0, averageCount))
                    )
                    .foregroundStyle(.orange)
                    .opacity(index % 2 == 0 ? 0.85 : 0.7)
                    .cornerRadius(2)
                    .position(by: .value("Series", "Average"))
                }
            }
        }
    }

    // Only highlight the bar if it's truly live data (current hour with data)
    func shouldHighlightBar(for hour: String) -> Bool {
        guard isLiveData else { return false }
        guard let mostRecentDataTime = mostRecentDataTime else { return false }
        return hour == mostRecentDataTime
    }
}

struct YAxisOffsetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .offset(x: -5) // Adjust the x offset as needed
    }
}

struct LegendViewDay: View {
    var selectedDate: String
    var isTodayView: Bool
    var isDeviceOnline: Bool
    var showAverage: Bool
    var isLiveData: Bool // True only when current hour has data and device is online
    @State private var showAlert = false
    @State private var showLiveAlert = false

    var body: some View {
        HStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
            Text(selectedDate)
                .font(.caption)
                .foregroundColor(.primary)

            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
            Button(action: {
                self.showAlert = true
            }) {
                HStack{
                    Text("Daily Average")
                        .foregroundColor(.primary)
                        .font(.caption)
                    Image(systemName:"info.circle.fill")
                        .foregroundColor(.primary)
                }
                .font(.caption)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Daily Average"),
                      message: Text("""
                                  The average is calculated based on data from the same weekday over the previous 8 weeks, provided there is enough data. \nA minimum of 2 weeks of data is required.\n\nIf there isn't sufficient data, the average will not be displayed on the graph.
                                  """),
                      dismissButton: .default(Text("OK")))
            }

            // Show green indicator only when we have live data for the current hour
            if isLiveData {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                Button(action: {
                    self.showLiveAlert = true
                }) {
                    HStack{
                        Text("Live Data")
                            .foregroundColor(.primary)
                            .font(.caption)
                        Image(systemName:"info.circle.fill")
                            .foregroundColor(.primary)
                    }
                    .font(.caption)
                }
                .alert(isPresented: $showLiveAlert) {
                    Alert(title: Text("Info for Live Data"),
                          message: Text("""
                                      The Live Data shows real-time data for the current hour. This updates automatically every 30 seconds to reflect the latest count.
                                      """),
                          dismissButton: .default(Text("OK")))
                }
            }
        }
        .padding(.horizontal)
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
