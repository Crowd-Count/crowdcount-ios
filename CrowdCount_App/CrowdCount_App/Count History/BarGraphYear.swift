import SwiftUI
import Charts

struct BarGraphYear: View {
    var yearData: [String: Double]
    var averageYearData: [String: Double]?
    var selectedYear: String
    var body: some View {
        VStack {
            Chart {
                barMarks()
                averageBarMarks()
            }
            .chartXAxis {
                AxisMarks(values: getAllMonths()) { value in
                    AxisValueLabel {
                        Text(getAbbreviatedMonthName(from: value.as(String.self) ?? ""))
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
            .chartYScale(domain: 0...(max(1, yearData.values.map { rounded($0) }.max() ?? 1, averageYearData?.values.map { rounded($0) }.max() ?? 1)))
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewYear(
                selectedYear: selectedYear,
                showAverage: averageYearData != nil
            )
            .padding(.top, 20)
        }
        .padding([.top, .bottom])
    }

    private func rounded(_ value: Double) -> Double {
        let r = value.rounded()
        return r < 1 ? 0 : r
    }

    @ChartContentBuilder
    private func barMarks() -> some ChartContent {
        let allMonths = getAllMonths()
        ForEach(Array(allMonths.enumerated()), id: \.element) { index, month in
            let count = rounded(yearData[month] ?? 0)
            BarMark(
                x: .value("Month", month),
                y: .value("Count", count)
            )
            .foregroundStyle(.blue)
            .opacity(index % 2 == 0 ? 1.0 : 0.85)
            .cornerRadius(3)
            .position(by: .value("Series", "Data"))
        }
    }

    @ChartContentBuilder
    private func averageBarMarks() -> some ChartContent {
        if let averageYearData = averageYearData {
            let allMonths = getAllMonths()
            ForEach(Array(allMonths.enumerated()), id: \.element) { index, month in
                if let averageCount = averageYearData[month], rounded(averageCount) > 0 {
                    BarMark(
                        x: .value("Month", month),
                        y: .value("Count", rounded(averageCount))
                    )
                    .foregroundStyle(.orange)
                    .opacity(index % 2 == 0 ? 0.85 : 0.7)
                    .cornerRadius(3)
                    .position(by: .value("Series", "Average"))
                }
            }
        }
    }

    private func getAllMonths() -> [String] {
        return ["January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"]
    }

    private func getAbbreviatedMonthName(from month: String) -> String {
        return String(month.prefix(3))
    }
}

struct LegendViewYear: View {
    var selectedYear: String
    var showAverage: Bool
    @State private var showAlert = false

    var body: some View {
        HStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
            Text(selectedYear)
                .font(.caption)
                .foregroundColor(.primary)

            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
            Button(action: {
                self.showAlert = true
            }) {
                HStack{
                    Text("Yearly Average")
                        .foregroundColor(.primary)
                    Image(systemName:"info.circle.fill")
                        .foregroundColor(.primary)
                }
                .font(.caption)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Yearly Average"),
                      message: Text("""
                                  The average is calculated based on data from the same month over the previous 3 years, provided there is enough data. \n\nIf there isn't sufficient data, the average will not be displayed on the graph.
                                  """),
                      dismissButton: .default(Text("OK")))
            }
        }
        .padding(.horizontal)
    }
}

struct BarGraphYear_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Preview with data and averages
            BarGraphYear(
                yearData: [
                    "January": 45.2, "February": 42.8, "March": 48.1, "April": 52.3,
                    "May": 55.7, "June": 58.9
                ],
                averageYearData: [
                    "January": 43.0, "February": 41.5, "March": 46.8, "April": 50.2,
                    "May": 53.4, "June": 56.7
                ],
                selectedYear: "2024"
            )
            .frame(height: 300)

            Divider()

            // Preview with data but no averages
            BarGraphYear(
                yearData: [
                    "January": 45.2, "February": 42.8, "March": 48.1
                ],
                averageYearData: nil,
                selectedYear: "2024"
            )
            .frame(height: 300)
        }
    }
}
