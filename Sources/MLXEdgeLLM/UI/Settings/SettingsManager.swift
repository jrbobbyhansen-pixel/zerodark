import SwiftUI
import Foundation

// MARK: - SettingsManager

class SettingsManager: ObservableObject {
    @Published var categories: [SettingsCategory] = [
        SettingsCategory(title: "General", items: [
            SettingsItem(title: "Notifications", type: .toggle, value: true),
            SettingsItem(title: "Sound Effects", type: .toggle, value: false)
        ]),
        SettingsCategory(title: "Privacy", items: [
            SettingsItem(title: "Location Sharing", type: .toggle, value: false),
            SettingsItem(title: "Data Analytics", type: .toggle, value: true)
        ]),
        SettingsCategory(title: "Advanced", items: [
            SettingsItem(title: "Debug Mode", type: .toggle, value: false),
            SettingsItem(title: "Performance Mode", type: .toggle, value: true)
        ])
    ]
    
    @Published var searchText: String = ""
    
    func resetSettings() {
        categories.forEach { category in
            category.items.forEach { item in
                switch item.type {
                case .toggle:
                    item.value = false
                case .slider:
                    item.value = 0.5
                case .text:
                    item.value = ""
                }
            }
        }
    }
    
    func importSettings(from data: Data) {
        // Placeholder for import logic
    }
    
    func exportSettings() -> Data? {
        // Placeholder for export logic
        return nil
    }
}

// MARK: - SettingsCategory

struct SettingsCategory: Identifiable {
    let id = UUID()
    let title: String
    var items: [SettingsItem]
}

// MARK: - SettingsItem

struct SettingsItem: Identifiable {
    let id = UUID()
    let title: String
    let type: SettingsItemType
    var value: Any
}

// MARK: - SettingsItemType

enum SettingsItemType {
    case toggle
    case slider
    case text
}

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $settingsManager.searchText)
                
                List(filteredCategories, id: \.id) { category in
                    Section(header: Text(category.title)) {
                        ForEach(category.items, id: \.id) { item in
                            switch item.type {
                            case .toggle:
                                Toggle(item.title, isOn: Binding(get: {
                                    if let value = item.value as? Bool {
                                        return value
                                    }
                                    return false
                                }, set: { newValue in
                                    item.value = newValue
                                }))
                            case .slider:
                                Slider(value: Binding(get: {
                                    if let value = item.value as? Double {
                                        return value
                                    }
                                    return 0.5
                                }, set: { newValue in
                                    item.value = newValue
                                }), in: 0...1)
                                .padding(.leading)
                            case .text:
                                TextField(item.title, text: Binding(get: {
                                    if let value = item.value as? String {
                                        return value
                                    }
                                    return ""
                                }, set: { newValue in
                                    item.value = newValue
                                }))
                                .padding(.leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Reset Settings") {
                            settingsManager.resetSettings()
                        }
                        Button("Import Settings") {
                            // Placeholder for import action
                        }
                        Button("Export Settings") {
                            // Placeholder for export action
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var filteredCategories: [SettingsCategory] {
        if searchText.isEmpty {
            return settingsManager.categories
        } else {
            return settingsManager.categories.filter { category in
                category.items.contains { item in
                    item.title.lowercased().contains(searchText.lowercased())
                }
            }
        }
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            TextField("Search", text: $text)
                .padding(7)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 10)
            
            if !text.isEmpty {
                Button(action: {
                    self.text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .padding(.trailing, 8)
                }
            }
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}