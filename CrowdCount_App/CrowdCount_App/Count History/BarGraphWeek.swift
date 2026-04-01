import SwiftUI

struct BarGraphWeek: View {
    var weekData: [String: Double]
    var averageWeekData: [String: Double]?
    var selectedDate: String

    // POS overlay
    var posWeekData: [String: Int]? = nil
    var showPOSOverlay: Bool = false

    private let allDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack {
            CombinedChartUIView(
                barData: weekData,
                averageData: averageWeekData,
                labels: allDays,
                displayLabels: shortDays,
                posData: posWeekData,
                showPOS: showPOSOverlay
            )
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewWeek(
                selectedDate: selectedDate,
                isTodayView: false,
                isDeviceOnline: false,
                showAverage: averageWeekData != nil,
                showPOS: showPOSOverlay
            )
            .padding(.top, 20)
        }
        .padding([.top, .bottom])
    }
}

struct LegendViewWeek: View {
    var selectedDate: String
    var isTodayView: Bool
    var isDeviceOnline: Bool
    var showAverage: Bool
    var showPOS: Bool = false
    @State private var showAlert = false

    var body: some View {
        FlowLayout(spacing: 6) {
            legendItem(color: .blue, text: selectedDate)

            Button(action: { self.showAlert = true }) {
                legendItem(color: .orange, text: "Weekly Average", showInfo: true)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Weekly Average"),
                      message: Text("The average is calculated based on data from the previous 4 weeks, provided there is enough data.\n\nIf there isn't sufficient data, the average will not be displayed on the graph."),
                      dismissButton: .default(Text("OK")))
            }

            if isTodayView && isDeviceOnline {
                legendItem(color: .green, text: "Today")
            }

            if showPOS {
                legendItem(color: .green, text: "Transactions", isDashed: true)
            }
        }
        .padding(.horizontal)
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
