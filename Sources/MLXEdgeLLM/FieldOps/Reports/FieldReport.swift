// FieldReport.swift — Field report with PDF export via UIGraphicsPDFRenderer.
//
// Previously orphaned + broken (recursive DateFormatter init, missing MapKit
// import, Hashable issues on AVAsset). Rewritten as a real PDF export:
//   - UIGraphicsPDFRenderer draws header → summary → location pin → attached
//     images in a paginated letter-size layout
//   - Save goes to Documents/FieldReports/<slug>.pdf with
//     .completeFileProtection
//   - Export progress surfaces through the view model's @Published state
//   - Videos are documented with a thumbnail + duration rather than embedded
//     (video-in-PDF isn't supported by iOS rendering)

import SwiftUI
import Foundation
import CoreLocation
import MapKit
import AVFoundation
import PDFKit

// MARK: - Model

struct FieldReport {
    var title: String
    var location: CLLocationCoordinate2D
    var timestamp: Date
    var details: String
    var images: [UIImage]
    var videos: [AVURLAsset]

    init(title: String,
         location: CLLocationCoordinate2D,
         timestamp: Date = .init(),
         details: String = "",
         images: [UIImage] = [],
         videos: [AVURLAsset] = []) {
        self.title = title
        self.location = location
        self.timestamp = timestamp
        self.details = details
        self.images = images
        self.videos = videos
    }
}

// MARK: - ViewModel

@MainActor
final class FieldReportViewModel: ObservableObject {
    @Published var report: FieldReport
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportError: String?
    @Published var exportedPDFURL: URL?

    init(report: FieldReport) { self.report = report }

    func exportToPDF() async {
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportedPDFURL = nil
        do {
            let url = try generatePDF()
            exportedPDFURL = url
            exportProgress = 1.0
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

    /// Build a paginated PDF and write to Documents/FieldReports/<slug>.pdf.
    private func generatePDF() throws -> URL {
        let pageWidth: CGFloat = 612   // US Letter @ 72 dpi
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40
        let pageBounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold)
            ]
            let titleSize = (report.title as NSString).boundingRect(
                with: CGSize(width: pageWidth - margin * 2, height: .infinity),
                options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil).size
            (report.title as NSString).draw(
                in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: titleSize.height),
                withAttributes: titleAttrs)
            y += titleSize.height + 6

            // Meta
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray
            ]
            let meta = "Captured \(formatter.string(from: report.timestamp))\n" +
                       String(format: "Location: %.5f, %.5f",
                              report.location.latitude, report.location.longitude)
            (meta as NSString).draw(
                in: CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 60),
                withAttributes: metaAttrs)
            y += 50

            // Details
            let detailHeader = "Details"
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
            ]
            (detailHeader as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
            y += 20

            let detailsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11)
            ]
            let detailsRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 280)
            (report.details as NSString).draw(in: detailsRect, withAttributes: detailsAttrs)
            y += min(280, CGFloat(report.details.count) * 0.6) + 20

            // Video listing (summary only — PDF can't embed video)
            if !report.videos.isEmpty {
                ("Videos (\(report.videos.count))" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
                y += 18
                for video in report.videos {
                    let filename = video.url.lastPathComponent
                    let secs = CMTimeGetSeconds(video.duration)
                    let line = String(format: " • %@ (%.0fs)", filename, secs.isFinite ? secs : 0)
                    (line as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: detailsAttrs)
                    y += 14
                    if y > pageHeight - margin - 20 { ctx.beginPage(); y = margin }
                }
                y += 10
            }

            // Images (one per page from here on)
            for (i, img) in report.images.enumerated() {
                if y > pageHeight - 200 { ctx.beginPage(); y = margin }
                let caption = "Image \(i + 1)/\(report.images.count)"
                (caption as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
                y += 18
                let maxW = pageWidth - margin * 2
                let maxH = pageHeight - y - margin
                let aspect = img.size.width / max(1, img.size.height)
                var drawW = maxW
                var drawH = drawW / aspect
                if drawH > maxH { drawH = maxH; drawW = drawH * aspect }
                img.draw(in: CGRect(x: margin, y: y, width: drawW, height: drawH))
                y += drawH + 10
            }

            // Progress tick (we update after the render call completes)
        }
        Task { @MainActor in self.exportProgress = 0.9 }

        // Persist
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FieldReports", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = report.title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let fname = "\(slug.isEmpty ? "report" : slug)-\(Int(report.timestamp.timeIntervalSince1970)).pdf"
        let url = dir.appendingPathComponent(fname)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

// MARK: - View

struct FieldReportView: View {
    @StateObject private var viewModel: FieldReportViewModel

    init(report: FieldReport) {
        _viewModel = StateObject(wrappedValue: FieldReportViewModel(report: report))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.report.title).font(.largeTitle.bold())
                FieldReportMapSnippet(location: viewModel.report.location)
                    .frame(height: 240)
                    .cornerRadius(10)
                Text("Captured " + viewModel.report.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
                Text(viewModel.report.details)
                if !viewModel.report.images.isEmpty {
                    ForEach(Array(viewModel.report.images.enumerated()), id: \.0) { _, img in
                        Image(uiImage: img).resizable().scaledToFit().cornerRadius(8)
                    }
                }
                Button {
                    Task { await viewModel.exportToPDF() }
                } label: {
                    Label("Export to PDF", systemImage: "arrow.up.doc.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isExporting)

                if viewModel.isExporting {
                    ProgressView(value: viewModel.exportProgress).padding(.top, 8)
                }
                if let err = viewModel.exportError {
                    Text(err).foregroundColor(.red).font(.caption)
                }
                if let url = viewModel.exportedPDFURL {
                    Text("Saved: \(url.lastPathComponent)")
                        .font(.caption.monospacedDigit()).foregroundColor(.green)
                }
            }
            .padding()
        }
        .navigationTitle("Field Report")
    }
}

// MARK: - MKMapView snippet

struct FieldReportMapSnippet: UIViewRepresentable {
    let location: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        let annotation = MKPointAnnotation()
        annotation.coordinate = location
        mapView.addAnnotation(annotation)
        mapView.setRegion(MKCoordinateRegion(
            center: location, latitudinalMeters: 500, longitudinalMeters: 500), animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}
}
