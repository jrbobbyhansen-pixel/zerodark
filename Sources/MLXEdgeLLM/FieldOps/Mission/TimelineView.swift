import SwiftUI
import Combine

// MARK: - Models

struct MissionEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let dependencies: [UUID]
}

struct MissionTimeline: Identifiable {
    let id = UUID()
    let title: String
    let events: [MissionEvent]
}

// MARK: - View Models

class MissionTimelineViewModel: ObservableObject {
    @Published var timeline: MissionTimeline
    
    init(timeline: MissionTimeline) {
        self.timeline = timeline
    }
}

// MARK: - Views

struct TimelineView: View {
    @StateObject private var viewModel: MissionTimelineViewModel
    
    init(timeline: MissionTimeline) {
        _viewModel = StateObject(wrappedValue: MissionTimelineViewModel(timeline: timeline))
    }
    
    var body: some View {
        VStack {
            Text(viewModel.timeline.title)
                .font(.largeTitle)
                .padding()
            
            TimelineChart(events: viewModel.timeline.events)
                .padding()
        }
        .navigationTitle("Mission Timeline")
    }
}

struct TimelineChart: View {
    let events: [MissionEvent]
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(events) { event in
                EventRow(event: event)
            }
        }
    }
}

struct EventRow: View {
    let event: MissionEvent
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.title)
                    .font(.headline)
                Text(event.startDate, style: .date)
                    .font(.subheadline)
            }
            Spacer()
            Text(event.endDate, style: .date)
                .font(.subheadline)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Previews

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let timeline = MissionTimeline(
            title: "Operation Alpha",
            events: [
                MissionEvent(title: "Deploy Team", startDate: Date(), endDate: Date().addingTimeInterval(3600), dependencies: []),
                MissionEvent(title: "Secure Location", startDate: Date().addingTimeInterval(3600), endDate: Date().addingTimeInterval(7200), dependencies: [UUID()]),
                MissionEvent(title: "Extract Data", startDate: Date().addingTimeInterval(7200), endDate: Date().addingTimeInterval(10800), dependencies: [UUID()])
            ]
        )
        
        TimelineView(timeline: timeline)
    }
}