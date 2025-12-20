import SwiftUI
import Charts

struct BarGraphWeek: View {
    var weekData: [String: Double]
    var averageWeekData: [String: Double]?
    var selectedDate: String

    var body: some View {
        VStack {
            Chart {
                barMarks()
                lineMarks()
            }
            .chartXAxis {
                AxisMarks(values: weekData.keys.sorted(by: { getWeekdayIndex(day: $0) < getWeekdayIndex(day: $1) })) { value in
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
        let sortedWeekDataKeys = weekData.keys.sorted(by: { getWeekdayIndex(day: $0) < getWeekdayIndex(day: $1) })
        ForEach(Array(sortedWeekDataKeys.enumerated()), id: \.element) { index, day in
            if let count = weekData[day] {
                BarMark(
                    x: .value("Day", day),
                    y: .value("Count", max(0, count))
                )
                .foregroundStyle(.blue)
                .opacity(index % 2 == 0 ? 0.8 : 0.6)
                .cornerRadius(3)
            }
        }
    }
    
    @ChartContentBuilder
    private func lineMarks() -> some ChartContent {
        let sortedWeekDataKeys = weekData.keys.sorted(by: { getWeekdayIndex(day: $0) < getWeekdayIndex(day: $1) })
        if let averageWeekData = averageWeekData {
            ForEach(sortedWeekDataKeys, id: \.self) { day in
                if let averageCount = averageWeekData[day] {
                    LineMark(
                        x: .value("Day", day),
                        y: .value("Average Count", max(0, averageCount))
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
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
