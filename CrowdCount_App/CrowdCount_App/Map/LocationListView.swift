import SwiftUI
import CoreLocation

// MARK: - LocationListView

struct LocationListView: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var filteredLocations: [Location] {
        if searchText.isEmpty {
            return viewModel.locations
        } else {
            return viewModel.locations.filter { location in
                location.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // List of Locations
                if filteredLocations.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No locations available" : "No locations found")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredLocations) { location in
                            LocationRowView(location: location)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
//                                .listRowBackground(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground))
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
                }
            }
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(colorScheme)
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search locations...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.primary)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(UIColor.tertiarySystemBackground) : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - LocationRowView

struct LocationRowView: View {
    let location: Location
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            ZStack {
                Circle()
                    .fill(Color.fromString(location.color).opacity(0.2))
                    .frame(width: 45, height: 45)

                Image(systemName: location.icon)
                    .font(.system(size: 20))
                    .foregroundColor(Color.fromString(location.color))
            }

            // Location Info
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    // Current Count with trend
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(location.currentCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        if location.comparison != "neutral" {
                            Text(location.comparisonSymbol)
                                .font(.subheadline)
                                .foregroundColor(location.comparisonColor)
                                .fontWeight(.bold)
                        }
                    }

                    // Overcrowding if available
                    if let overcrowding = location.overcrowding {
                        Text("Max: \(overcrowding)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
