import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - PointCloudAnnotator

class PointCloudAnnotator: ObservableObject {
    @Published var annotations: [Annotation] = []
    @Published var selectedAnnotation: Annotation?
    
    func addAnnotation(at location: CLLocationCoordinate2D, note: String) {
        let annotation = Annotation(location: location, note: note)
        annotations.append(annotation)
    }
    
    func removeAnnotation(_ annotation: Annotation) {
        annotations.removeAll { $0.id == annotation.id }
    }
    
    func selectAnnotation(_ annotation: Annotation) {
        selectedAnnotation = annotation
    }
    
    func clearAnnotations() {
        annotations.removeAll()
    }
}

// MARK: - Annotation

struct Annotation: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let note: String
}

// MARK: - PointCloudAnnotatorView

struct PointCloudAnnotatorView: View {
    @StateObject private var viewModel = PointCloudAnnotator()
    @State private var isAddingNote = false
    @State private var newNote = ""
    
    var body: some View {
        VStack {
            $name(annotations: viewModel.annotations, selectedAnnotation: $viewModel.selectedAnnotation)
                .edgesIgnoringSafeArea(.all)
            
            HStack {
                Button(action: {
                    isAddingNote = true
                }) {
                    Text("Add Note")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button(action: {
                    viewModel.clearAnnotations()
                }) {
                    Text("Clear All")
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .sheet(isPresented: $isAddingNote) {
            AddNoteView(viewModel: viewModel, newNote: $newNote, isAddingNote: $isAddingNote)
        }
    }
}

// MARK: - AddNoteView

struct AddNoteView: View {
    @ObservedObject var viewModel: PointCloudAnnotator
    @Binding var newNote: String
    @Binding var isAddingNote: Bool
    
    var body: some View {
        VStack {
            TextField("Enter note", text: $newNote)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                if let selectedLocation = viewModel.selectedAnnotation?.location {
                    viewModel.addAnnotation(at: selectedLocation, note: newNote)
                }
                isAddingNote = false
                newNote = ""
            }) {
                Text("Add")
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - MapView

struct PointCloudMapSnippet: UIViewRepresentable {
    let annotations: [Annotation]
    @Binding var selectedAnnotation: Annotation?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        let mapAnnotations = annotations.map { MapAnnotation(annotation: $0) }
        uiView.addAnnotations(mapAnnotations)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? MapAnnotation {
                parent.selectedAnnotation = annotation.annotation
            }
        }
    }
}

// MARK: - MapAnnotation

class MapAnnotation: NSObject, MKAnnotation {
    let annotation: Annotation
    
    var coordinate: CLLocationCoordinate2D {
        return annotation.location
    }
    
    var title: String? {
        return annotation.note
    }
    
    init(annotation: Annotation) {
        self.annotation = annotation
    }
}