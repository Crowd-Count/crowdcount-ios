import SwiftUI
import Charts

struct BarGraphWeek: View {
    var weekData: [String: Double]
    var averageWeekData: [String: Double]?
    var selectedDate: String

    // All days of the week in order
    private let allDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        VStack {
            Chart {
                barMarks()
                averageBarMarks()
            }
            .chartXAxis {
                AxisMarks(values: allDays) { value in
                    AxisValueLabel {
                        Text(getAbbreviatedDayName(from: value.as(String.self) ?? ""))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { value in
                    AxisValueLabel {
                        Text(value.as(Int.self)?.description ?? "")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.5))
                }
            }
            .chartYScale(domain: 0...(max(1, weekData.values.map { max(0, $0) }.max() ?? 1, averageWeekData?.values.map { max(0, $0) }.max() ?? 1)))
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewWeek(selectedDate: selectedDate, isTodayView: false, isDeviceOnline: false, showAverage: averageWeekData != nil)
                .padding(.top, 20) // Adjust padding for more space between graph and legend
        }
        .padding([.top, .bottom]) // Add padding to top and bottom of the view
    }

    @ChartContentBuilder
    private func barMarks() -> some ChartContent {
        // Show bars for all days - visible ones for days with data, invisible placeholders for days without
        ForEach(Array(allDays.enumerated()), id: \.element) { index, day in
            let count = weekData[day] ?? 0
            if count > 0 {
                // Actual bar for days with data
                BarMark(
                    x: .value("Day", day),
                    y: .value("Count", count)
                )
                .foregroundStyle(.blue)
                .opacity(index % 2 == 0 ? 1.0 : 0.85)
                .cornerRadius(3)
                .position(by: .value("Series", "Data"))
            } else {
                // Invisible placeholder to ensure day appears on X-axis
                BarMark(
                    x: .value("Day", day),
                    y: .value("Count", 0)
                )
                .foregroundStyle(.clear)
                .position(by: .value("Series", "Data"))
            }
        }
    }

    @ChartContentBuilder
    private func averageBarMarks() -> some ChartContent {
        if let averageWeekData = averageWeekData {
            ForEach(Array(allDays.enumerated()), id: \.element) { index, day in
                if let averageCount = averageWeekData[day] {
                    BarMark(
                        x: .value("Day", day),
                        y: .value("Count", max(0, averageCount))
                    )
                    .foregroundStyle(.orange)
                    .opacity(index % 2 == 0 ? 0.85 : 0.7)
                    .cornerRadius(3)
                    .position(by: .value("Series", "Average"))
                }
            }
        }
    }

    private func getWeekdayIndex(day: String) -> Int {
        switch day {
        case "Monday": return 0
        case "Tuesday": return 1
        case "Wednesday": return 2
        case "Thursday": return 3
        case "Friday": return 4
        case "Saturday": return 5
        case "Sunday": return 6
        default: return 7
        }
    }

    private func getAbbreviatedDayName(from day: String) -> String {
        return String(day.prefix(3))
    }
}

struct LegendViewWeek: View {
    var selectedDate: String
    var isTodayView: Bool
    var isDeviceOnline: Bool
    var showAverage: Bool
    @State private var showAlert = false

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
                    Text("Weekly Average")
                        .foregroundColor(.primary)
                    Image(systemName:"info.circle.fill")
                        .foregroundColor(.primary)
                }
                .font(.caption)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Weekly Average"),
                      message: Text("""
                                  The average is calculated based on data from the previous 4 weeks, provided there is enough data. \n\nIf there isn't sufficient data, the average will not be displayed on the graph.
                                  """),
                      dismissButton: .default(Text("OK")))
            }

            if isTodayView && isDeviceOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                Text("Today")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
    }
}

struct BarGraphWeek_Previews: PreviewProvider {
    static var previews: some View {
        BarGraphWeek(
            weekData: ["Monday": 14.8, "Tuesday": 15.1, "Wednesday": 15.9, "Thursday": 16.2, "Friday": 14.7, "Saturday": 15.3, "Sunday": 14.4],
            averageWeekData: ["Monday": 14.8, "Tuesday": 15.1, "Wednesday": 15.9, "Thursday": 16.2, "Friday": 14.7, "Saturday": 15.3, "Sunday": 14.4],
            selectedDate: "Week of July 9, 2024"
        )
        .frame(height: 300)
    }
}
