import SwiftUI
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

// Entry data response models (entries track people who entered, not population)
struct EntryDayDataResponse: Decodable {
    let entry_day_data: [String: Double]
}

struct AverageEntryDayDataResponse: Decodable {
    let average_entry_day_data: [String: Double]
}

struct EntryWeekDataResponse: Decodable {
    let entry_week_data: [String: Double]
}

struct AverageEntryWeekDataResponse: Decodable {
    let average_entry_week_data: [String: Double]
}

struct EntryYearDataResponse: Decodable {
    let entry_year_data: [String: Double]
}

struct AverageEntryYearDataResponse: Decodable {
    let average_entry_year_data: [String: Double]
}

// Data type toggle for graphs
enum GraphDataType: String, CaseIterable {
    case population = "Population"
    case entries = "Entries"
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

enum HistoricViewTab: String, CaseIterable {
    case historicCounts = "Historic Counts"
    case insights = "Insights"
}

// MARK: - UIApplication Extension

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
