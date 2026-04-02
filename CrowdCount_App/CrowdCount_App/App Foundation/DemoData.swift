import Foundation
import CoreLocation

/// Centralized demo data for screenshot mode.
/// Used when `AppSettings.demo` and/or `AppSettings.hasDevicesAddedForDemo` are true.
enum DemoData {

    // MARK: - Map Locations

    static let locations: [Location] = [
        Location(
            id: "demo-hq",
            name: "CrowdCount HQ",
            coordinate: CLLocationCoordinate2D(latitude: 40.0192959, longitude: -105.28284905),
            deviceIds: ["T0001"],
            color: "red",
            icon: "flag.2.crossed.fill",
            currentCount: 5,
            isClosed: false,
            comparison: "up",
            overcrowding: 10,
            allDevicesOnline: true
        ),
        Location(
            id: "demo-park",
            name: "City Park",
            coordinate: CLLocationCoordinate2D(latitude: 40.01783, longitude: -105.2684),
            deviceIds: ["T0002"],
            color: "green",
            icon: "tree.fill",
            currentCount: 23,
            isClosed: false,
            comparison: "down",
            overcrowding: nil,
            allDevicesOnline: true
        ),
        Location(
            id: "demo-lake",
            name: "Crowded Lake",
            coordinate: CLLocationCoordinate2D(latitude: 40.00087, longitude: -105.25944),
            deviceIds: ["T0000"],
            color: "blue",
            icon: "fish.fill",
            currentCount: 29,
            isClosed: false,
            comparison: "neutral",
            overcrowding: nil,
            allDevicesOnline: true
        ),
        Location(
            id: "demo-pub",
            name: "McCrowd's Pub",
            coordinate: CLLocationCoordinate2D(latitude: 40.00846, longitude: -105.27546),
            deviceIds: ["Demo"],
            color: "orange",
            icon: "mug.fill",
            currentCount: 86,
            isClosed: false,
            comparison: "up",
            overcrowding: 100,
            allDevicesOnline: true
        )
    ]

    // MARK: - Promotions / Ads

    static let ads: [ServerAd] = [
        ServerAd(
            id: "demo-ad-hq",
            title: "CrowdCount HQ",
            description: "Visit our headquarters! Free demo and swag.",
            imagePath: nil,
            locationId: "T0001",
            durationHours: 24,
            totalPrice: 120.0,
            ctaText: "Visit Us",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 3600 + 34 * 60)),
            demoIcon: "flag.2.crossed.fill",
            demoColor: "red",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.0192959, longitude: -105.28284905)
        ),
        ServerAd(
            id: "demo-ad-park",
            title: "City Park",
            description: "Nature walks every weekend. Join the community!",
            imagePath: nil,
            locationId: "T0002",
            durationHours: 48,
            totalPrice: 240.0,
            ctaText: "Join Now",
            ctaLinkType: "custom",
            ctaURL: "https://crowdcount.tech",
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 3600 + 12 * 60)),
            demoIcon: "tree.fill",
            demoColor: "green",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.01783, longitude: -105.2684)
        ),
        ServerAd(
            id: "demo-ad-lake",
            title: "Crowded Lake",
            description: "Paddleboard rentals 50% off today!",
            imagePath: nil,
            locationId: "T0000",
            durationHours: 12,
            totalPrice: 60.0,
            ctaText: "Book Now",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(45 * 60)),
            demoIcon: "fish.fill",
            demoColor: "blue",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.00087, longitude: -105.25944)
        ),
        ServerAd(
            id: "demo-ad-pub",
            title: "McCrowd's Pub",
            description: "$2 draft pints for the next hour!",
            imagePath: nil,
            locationId: "Demo",
            durationHours: 1,
            totalPrice: 5.0,
            ctaText: "View Details",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1 * 3600)),
            demoIcon: "mug.fill",
            demoColor: "orange",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.00846, longitude: -105.27546)
        )
    ]

    // MARK: - Popular Times (keyed by location id, UTC hour keys)

    static let popularTimes: [String: PopularTimesData] = {
        let offsetHours = TimeZone.current.secondsFromGMT() / 3600
        func utcKey(_ localHour: Int) -> String {
            String((localHour - offsetHours + 24) % 24)
        }

        // CrowdCount HQ — office pattern: peaks 10am-2pm
        let hq: [String: Double] = [
            utcKey(7): 1, utcKey(8): 3, utcKey(9): 6, utcKey(10): 8, utcKey(11): 9,
            utcKey(12): 10, utcKey(13): 9, utcKey(14): 8, utcKey(15): 6, utcKey(16): 4,
            utcKey(17): 2
        ]

        // City Park — morning + afternoon peaks
        let park: [String: Double] = [
            utcKey(6): 3, utcKey(7): 8, utcKey(8): 15, utcKey(9): 18, utcKey(10): 14,
            utcKey(11): 10, utcKey(12): 8, utcKey(13): 7, utcKey(14): 9, utcKey(15): 14,
            utcKey(16): 20, utcKey(17): 22, utcKey(18): 16, utcKey(19): 8, utcKey(20): 3
        ]

        // Crowded Lake — gentle midday peak
        let lake: [String: Double] = [
            utcKey(8): 2, utcKey(9): 5, utcKey(10): 10, utcKey(11): 18, utcKey(12): 24,
            utcKey(13): 28, utcKey(14): 26, utcKey(15): 20, utcKey(16): 14, utcKey(17): 8,
            utcKey(18): 4
        ]

        // McCrowd's Pub — classic pub: ramps from 4pm, peaks 8-10pm
        let pub: [String: Double] = [
            utcKey(11): 4, utcKey(12): 8, utcKey(13): 10, utcKey(14): 12, utcKey(15): 15,
            utcKey(16): 22, utcKey(17): 35, utcKey(18): 50, utcKey(19): 65, utcKey(20): 78,
            utcKey(21): 82, utcKey(22): 68, utcKey(23): 42, utcKey(0): 18
        ]

        let dayOfWeek: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEEE"
            return f.string(from: Date())
        }()

        return [
            "demo-hq": PopularTimesData(hourlyAveragesUTC: hq, dayOfWeek: dayOfWeek, busynessLevel: 2),
            "demo-park": PopularTimesData(hourlyAveragesUTC: park, dayOfWeek: dayOfWeek, busynessLevel: 3),
            "demo-lake": PopularTimesData(hourlyAveragesUTC: lake, dayOfWeek: dayOfWeek, busynessLevel: 3),
            "demo-pub": PopularTimesData(hourlyAveragesUTC: pub, dayOfWeek: dayOfWeek, busynessLevel: 4)
        ]
    }()

    // MARK: - Demo Device & AppLocation (for counter side)

    static let demoDevice = Device(id: UUID(), deviceId: "Demo", password: "demo")

    static let demoAppLocation = AppLocation(
        id: "demo-mccrowds-pub",
        name: "McCrowd's Pub",
        deviceIds: ["Demo"],
        overcrowdingLimit: 100,
        colorName: "orange",
        isOvercrowdingNotificationEnabled: false,
        isOnMap: true,
        mapIcon: "mug.fill",
        mapColor: "orange"
    )

    // MARK: - History Data (local-time hour keys, assigned directly to state — bypasses TZ shifting)

    /// Day population data — pub pattern (keys "0"-"23", local time)
    static let demoDayData: [String: Double] = [
        "11": 8, "12": 12, "13": 15, "14": 18, "15": 22, "16": 30,
        "17": 42, "18": 58, "19": 72, "20": 86, "21": 88, "22": 75,
        "23": 52, "0": 28
    ]

    static let demoAvgDayData: [String: Double] = [
        "11": 6, "12": 10, "13": 14, "14": 16, "15": 20, "16": 28,
        "17": 38, "18": 52, "19": 66, "20": 82, "21": 80, "22": 70,
        "23": 48, "0": 24
    ]

    /// Day entry data — cumulative entries per hour (higher than population)
    static let demoEntryDayData: [String: Double] = [
        "11": 8, "12": 18, "13": 22, "14": 25, "15": 30, "16": 38,
        "17": 52, "18": 68, "19": 78, "20": 92, "21": 85, "22": 60,
        "23": 35, "0": 15
    ]

    static let demoAvgEntryDayData: [String: Double] = [
        "11": 6, "12": 15, "13": 20, "14": 22, "15": 28, "16": 35,
        "17": 48, "18": 62, "19": 72, "20": 86, "21": 78, "22": 55,
        "23": 30, "0": 12
    ]

    /// Week data — keys are day names
    static let demoWeekData: [String: Double] = [
        "Monday": 42, "Tuesday": 48, "Wednesday": 52, "Thursday": 55,
        "Friday": 88, "Saturday": 92, "Sunday": 65
    ]

    static let demoAvgWeekData: [String: Double] = [
        "Monday": 38, "Tuesday": 44, "Wednesday": 48, "Thursday": 50,
        "Friday": 82, "Saturday": 85, "Sunday": 60
    ]

    static let demoEntryWeekData: [String: Double] = [
        "Monday": 125, "Tuesday": 138, "Wednesday": 152, "Thursday": 165,
        "Friday": 285, "Saturday": 310, "Sunday": 195
    ]

    static let demoAvgEntryWeekData: [String: Double] = [
        "Monday": 118, "Tuesday": 130, "Wednesday": 142, "Thursday": 155,
        "Friday": 268, "Saturday": 290, "Sunday": 180
    ]

    /// Year data — keys are month names
    static let demoYearData: [String: Double] = [
        "January": 38, "February": 42, "March": 48, "April": 55,
        "May": 62, "June": 72, "July": 78, "August": 75,
        "September": 65, "October": 58, "November": 45, "December": 52
    ]

    static let demoAvgYearData: [String: Double] = [
        "January": 35, "February": 40, "March": 45, "April": 50,
        "May": 58, "June": 68, "July": 74, "August": 72,
        "September": 62, "October": 55, "November": 42, "December": 48
    ]

    static let demoEntryYearData: [String: Double] = [
        "January": 3200, "February": 3500, "March": 4100, "April": 4800,
        "May": 5400, "June": 6200, "July": 6800, "August": 6500,
        "September": 5600, "October": 4900, "November": 3800, "December": 4400
    ]

    static let demoAvgEntryYearData: [String: Double] = [
        "January": 3000, "February": 3300, "March": 3900, "April": 4500,
        "May": 5100, "June": 5800, "July": 6400, "August": 6200,
        "September": 5300, "October": 4600, "November": 3600, "December": 4100
    ]

    // MARK: - Dwell Time

    static let demoDwellTimeMinutes: Double = 47.5

    static let demoWeekDwellTime: [String: Double] = [
        "Monday": 42, "Tuesday": 40, "Wednesday": 44, "Thursday": 45,
        "Friday": 55, "Saturday": 58, "Sunday": 48
    ]

    static let demoYearDwellTime: [String: Double] = [
        "January": 40, "February": 42, "March": 44, "April": 46,
        "May": 48, "June": 50, "July": 52, "August": 50,
        "September": 48, "October": 45, "November": 42, "December": 44
    ]

    // MARK: - POS Transaction Data

    /// Hourly POS data for today (local-time hour keys)
    static let posDayTransactions: [String: POSTransactionData.POSHourlyEntry] = [
        "11": POSTransactionData.POSHourlyEntry(transactions: 5, revenue: 7500),
        "12": POSTransactionData.POSHourlyEntry(transactions: 10, revenue: 16000),
        "13": POSTransactionData.POSHourlyEntry(transactions: 12, revenue: 19200),
        "14": POSTransactionData.POSHourlyEntry(transactions: 14, revenue: 22400),
        "15": POSTransactionData.POSHourlyEntry(transactions: 18, revenue: 28800),
        "16": POSTransactionData.POSHourlyEntry(transactions: 22, revenue: 35200),
        "17": POSTransactionData.POSHourlyEntry(transactions: 28, revenue: 42000),
        "18": POSTransactionData.POSHourlyEntry(transactions: 35, revenue: 52500),
        "19": POSTransactionData.POSHourlyEntry(transactions: 42, revenue: 63000),
        "20": POSTransactionData.POSHourlyEntry(transactions: 48, revenue: 76800),
        "21": POSTransactionData.POSHourlyEntry(transactions: 45, revenue: 72000),
        "22": POSTransactionData.POSHourlyEntry(transactions: 32, revenue: 51200),
        "23": POSTransactionData.POSHourlyEntry(transactions: 18, revenue: 28800),
        "0": POSTransactionData.POSHourlyEntry(transactions: 8, revenue: 12000)
    ]

    /// Weekly POS transaction counts (for green line on week chart)
    static let posWeekTransactions: [String: Int] = [
        "Monday": 120, "Tuesday": 135, "Wednesday": 148, "Thursday": 160,
        "Friday": 275, "Saturday": 295, "Sunday": 185
    ]

    /// Yearly POS transaction counts (for green line on year chart)
    static let posYearTransactions: [String: Int] = [
        "January": 3100, "February": 3400, "March": 3950, "April": 4600,
        "May": 5200, "June": 5900, "July": 6500, "August": 6300,
        "September": 5400, "October": 4700, "November": 3650, "December": 4200
    ]

    /// POS insights (period comparisons)
    static let posInsights: POSInsightsResponse = {
        let todayStats = POSPeriodStats(
            transactions: 337,
            revenue: 527400,   // $5,274
            currency: "USD",
            entries: 480,
            conversionRate: 70.2,
            revenuePerVisitor: 1099, // $10.99
            avgTransaction: 1565,    // $15.65
            hourlyData: nil
        )
        let prevDayStats = POSPeriodStats(
            transactions: 310,
            revenue: 484600,
            currency: "USD",
            entries: 450,
            conversionRate: 68.9,
            revenuePerVisitor: 1077,
            avgTransaction: 1563,
            hourlyData: nil
        )
        let weekStats = POSPeriodStats(
            transactions: 1318,
            revenue: 2062700, // $20,627
            currency: "USD",
            entries: 1870,
            conversionRate: 70.5,
            revenuePerVisitor: 1103,
            avgTransaction: 1565,
            hourlyData: nil
        )
        let prevWeekStats = POSPeriodStats(
            transactions: 1245,
            revenue: 1948200,
            currency: "USD",
            entries: 1790,
            conversionRate: 69.6,
            revenuePerVisitor: 1088,
            avgTransaction: 1565,
            hourlyData: nil
        )
        let yearStats = POSPeriodStats(
            transactions: 57000,
            revenue: 89205000, // $892,050
            currency: "USD",
            entries: 81200,
            conversionRate: 70.2,
            revenuePerVisitor: 1099,
            avgTransaction: 1565,
            hourlyData: nil
        )
        let prevYearStats = POSPeriodStats(
            transactions: 52800,
            revenue: 82632000,
            currency: "USD",
            entries: 76500,
            conversionRate: 69.0,
            revenuePerVisitor: 1080,
            avgTransaction: 1565,
            hourlyData: nil
        )
        return POSInsightsResponse(
            today: todayStats,
            prevDay: prevDayStats,
            week: weekStats,
            prevWeek: prevWeekStats,
            year: yearStats,
            prevYear: prevYearStats
        )
    }()
}
