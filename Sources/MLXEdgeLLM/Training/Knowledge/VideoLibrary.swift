import Foundation
import SwiftUI
import AVFoundation

// MARK: - Models

struct Video {
    let id: UUID
    let title: String
    let category: String
    let url: URL
    var isDownloaded: Bool = false
    var progress: Double = 0.0
}

class VideoLibrary: ObservableObject {
    @Published var videos: [Video] = []
    @Published var categories: [String] = []
    
    init() {
        loadVideos()
    }
    
    func loadVideos() {
        // Simulate loading videos from a data source
        videos = [
            Video(id: UUID(), title: "Introduction to AI", category: "Basics", url: URL(string: "https://example.com/video1")!),
            Video(id: UUID(), title: "Advanced AI Techniques", category: "Advanced", url: URL(string: "https://example.com/video2")!),
            Video(id: UUID(), title: "Machine Learning Basics", category: "Basics", url: URL(string: "https://example.com/video3")!),
        ]
        categories = Array(Set(videos.map { $0.category }))
    }
    
    func downloadVideo(_ video: Video) {
        // Simulate video download
        video.isDownloaded = true
        video.progress = 1.0
    }
    
    func searchVideos(query: String) -> [Video] {
        return videos.filter { $0.title.lowercased().contains(query.lowercased()) }
    }
}

// MARK: - Views

struct VideoLibraryView: View {
    @StateObject private var viewModel = VideoLibrary()
    @State private var searchText = ""
    @State private var selectedCategory: String?
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(viewModel.categories, id: \.self) { category in
                            Text(category)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding()
                }
                
                List(filteredVideos, id: \.id) { video in
                    VideoRow(video: video)
                        .onTapGesture {
                            // Navigate to video player
                        }
                }
            }
            .navigationTitle("Video Library")
        }
    }
    
    private var filteredVideos: [Video] {
        var filtered = viewModel.videos
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            filtered = viewModel.searchVideos(query: searchText)
        }
        return filtered
    }
}

struct VideoRow: View {
    let video: Video
    
    var body: some View {
        HStack {
            Text(video.title)
            Spacer()
            if video.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                ProgressView(value: video.progress)
                    .frame(width: 50)
            }
        }
    }
}

// MARK: - Preview

struct VideoLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        VideoLibraryView()
    }
}