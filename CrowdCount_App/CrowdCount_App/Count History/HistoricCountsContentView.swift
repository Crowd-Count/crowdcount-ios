import SwiftUI

struct HistoricCountsContentView: View {
    // Graph data type selection
    @Binding var selectedGraphDataType: GraphDataType

    // Day selection and data
    @Binding var selectedDay: String
    let availableDates: [String]
    let dayData: [String: Double]
    let averageDayData: [String: Double]?
    let hasDataForSelectedDay: Bool
    let isDayLoading: Bool
    let isDeviceOnline: Bool
    let mostRecentDataTime: String?

    // Entry day data
    let entryDayData: [String: Double]
    let averageEntryDayData: [String: Double]?
    let hasDataForSelectedDayEntries: Bool
    let isEntryDayLoading: Bool

    // Week selection and data
    @Binding var selectedWeek: WeekInfo?
    let availableWeeks: [WeekInfo]
    let weekData: [String: Double]
    let averageWeekData: [String: Double]?
    let hasDataForSelectedWeek: Bool
    let isWeekLoading: Bool

    // Entry week data
    let entryWeekData: [String: Double]
    let averageEntryWeekData: [String: Double]?
    let hasDataForSelectedWeekEntries: Bool
    let isEntryWeekLoading: Bool

    // Year selection and data
    @Binding var selectedYear: String
    let availableYears: [String]
    let yearData: [String: Double]
    let averageYearData: [String: Double]?
    let hasDataForSelectedYear: Bool
    let isYearLoading: Bool
    let hasInsufficientYearData: Bool

    // Entry year data
    let entryYearData: [String: Double]
    let averageEntryYearData: [String: Double]?
    let hasDataForSelectedYearEntries: Bool
    let isEntryYearLoading: Bool

    // Callbacks
    let onDaySelected: (String) -> Void
    let onWeekSelected: (WeekInfo) -> Void
    let onYearSelected: (String) -> Void
    let onDownloadDay: () -> Void
    let onDownloadWeek: () -> Void
    let onDownloadYear: () -> Void
    let getCurrentDate: () -> String
    let getCurrentYear: () -> String
    let formattedDateLong: (String) -> String
    let findMostRecentDataTime: ([String: Double]) -> String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Day view with chart and download button
                daySection

                // Weekly chart view with download button
                weekSection

                // Yearly chart view
                yearSection
            }
        }
    }

    // MARK: - Day Section

    private var daySection: some View {
        VStack {
            HStack {
                Menu {
                    ForEach(availableDates.sorted(by: >), id: \.self) { date in
                        let displayDate = (date == getCurrentDate()) ? "Today" : formattedDateLong(date)
                        Button(displayDate) {
                            onDaySelected(date)
                        }
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

                Button(action: onDownloadDay) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .offset(y: -3)
                }
                .padding()
            }

            ZStack {
                if selectedGraphDataType == .population {
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
                        noDataPlaceholder(message: "No data for today", submessage: "Please select another day")
                    }
                } else {
                    if hasDataForSelectedDayEntries {
                        BarGraphDay(
                            dayData: entryDayData,
                            averageDayData: averageEntryDayData,
                            isTodayView: selectedDay == "Today",
                            selectedDate: selectedDay,
                            isDeviceOnline: isDeviceOnline,
                            mostRecentDataTime: findMostRecentDataTime(entryDayData)
                        )
                        .frame(height: 250)
                    } else {
                        noDataPlaceholder(message: "No entry data for today", submessage: "Please select another day")
                    }
                }

                if (selectedGraphDataType == .population && isDayLoading) || (selectedGraphDataType == .entries && isEntryDayLoading) {
                    loadingOverlay
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
        .id("dayView")
    }

    // MARK: - Week Section

    private var weekSection: some View {
        VStack {
            HStack {
                Menu {
                    ForEach(availableWeeks) { week in
                        Button(week.label) {
                            onWeekSelected(week)
                        }
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

                Button(action: onDownloadWeek) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .offset(y: -3)
                }
                .padding()
            }

            ZStack {
                if selectedGraphDataType == .population {
                    if hasDataForSelectedWeek {
                        BarGraphWeek(
                            weekData: weekData,
                            averageWeekData: averageWeekData ?? [:],
                            selectedDate: selectedWeek?.label ?? ""
                        )
                        .frame(height: 250)
                    } else {
                        noDataPlaceholder(message: "No data for this week", submessage: "Please select another week")
                    }
                } else {
                    if hasDataForSelectedWeekEntries {
                        BarGraphWeek(
                            weekData: entryWeekData,
                            averageWeekData: averageEntryWeekData ?? [:],
                            selectedDate: selectedWeek?.label ?? ""
                        )
                        .frame(height: 250)
                    } else {
                        noDataPlaceholder(message: "No entry data for this week", submessage: "Please select another week")
                    }
                }

                if (selectedGraphDataType == .population && isWeekLoading) || (selectedGraphDataType == .entries && isEntryWeekLoading) {
                    loadingOverlay
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.1))
        .cornerRadius(30)
        .padding(.horizontal)
        .id("weekView")
    }

    // MARK: - Year Section

    private var yearSection: some View {
        VStack {
            HStack {
                Menu {
                    ForEach(availableYears, id: \.self) { year in
                        let displayYear = (year == getCurrentYear()) ? "This Year" : year
                        Button(displayYear) {
                            onYearSelected(year)
                        }
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

                Button(action: onDownloadYear) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .offset(y: -3)
                }
                .padding()
            }

            ZStack {
                if selectedGraphDataType == .population {
                    if hasDataForSelectedYear {
                        BarGraphYear(
                            yearData: yearData,
                            averageYearData: averageYearData,
                            selectedYear: selectedYear,
                            hasInsufficientData: hasInsufficientYearData
                        )
                        .frame(height: 250)
                    } else {
                        noDataPlaceholder(message: "No data for this year", submessage: "Please select another year")
                    }
                } else {
                    if hasDataForSelectedYearEntries {
                        BarGraphYear(
                            yearData: entryYearData,
                            averageYearData: averageEntryYearData,
                            selectedYear: selectedYear,
                            hasInsufficientData: averageEntryYearData == nil
                        )
                        .frame(height: 250)
                    } else {
                        noDataPlaceholder(message: "No entry data for this year", submessage: "Please select another year")
                    }
                }

                if (selectedGraphDataType == .population && isYearLoading) || (selectedGraphDataType == .entries && isEntryYearLoading) {
                    loadingOverlay
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.1))
        .cornerRadius(30)
        .padding(.horizontal)
        .id("yearView")
    }

    // MARK: - Helper Views

    private func noDataPlaceholder(message: String, submessage: String) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .cornerRadius(25)
            .frame(height: 250)
            .overlay(
                VStack {
                    Text(message)
                        .foregroundColor(.primary)
                        .bold()
                    Text(submessage)
                        .foregroundColor(.secondary)
                }
            )
    }

    private var loadingOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
            .frame(height: 250)
            .overlay(
                ProgressView()
                    .scaleEffect(1.2)
            )
    }
}
