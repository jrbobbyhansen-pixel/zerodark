// FastLibraryView.swift — Instant Search UI for Tactical Library

import SwiftUI
import PDFKit

struct FastLibraryView: View {
    @StateObject private var library = FastLibraryService.shared
    @State private var searchText = ""
    @State private var selectedDoc: LibraryDocument?
    @State private var selectedChunk: TextChunk?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Content
                if library.isIndexing {
                    indexingView
                } else if !searchText.isEmpty {
                    searchResultsView
                } else {
                    documentsListView
                }
            }
            .background(ZDDesign.darkBackground)
            .navigationTitle("Tactical Library")
            .sheet(item: $selectedDoc) { doc in
                PDFReaderSheet(document: doc, initialPage: selectedChunk?.page)
            }
            .task {
                await library.initialize()
            }
        }
    }

    // MARK: - Search Bar

    var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(ZDDesign.mediumGray)

            TextField("Search manuals...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(ZDDesign.pureWhite)
                .focused($searchFocused)
                .onChange(of: searchText) { _, newValue in
                    library.performSearch(newValue)
                }
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    library.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
    }

    // MARK: - Indexing View

    var indexingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(ZDDesign.cyanAccent)

            Text("Indexing PDFs...")
                .font(.headline)
                .foregroundColor(ZDDesign.pureWhite)

            ProgressView(value: library.indexProgress)
                .tint(ZDDesign.cyanAccent)
                .frame(width: 200)

            Text("\(Int(library.indexProgress * 100))%")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)

            Spacer()
        }
    }

    // MARK: - Search Results

    var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if library.searchResults.isEmpty && !searchText.isEmpty {
                    Text("No results for \"\(searchText)\"")
                        .foregroundColor(ZDDesign.mediumGray)
                        .padding(.top, 40)
                } else {
                    ForEach(library.searchResults) { chunk in
                        SearchResultRow(chunk: chunk) {
                            selectedChunk = chunk
                            if let doc = library.document(id: chunk.docId) {
                                selectedDoc = doc
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Documents List

    var documentsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if library.documents.isEmpty {
                    emptyState
                } else {
                    ForEach(library.documents) { doc in
                        DocumentRow(document: doc) {
                            selectedChunk = nil
                            selectedDoc = doc
                        }
                    }
                }
            }
            .padding()
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(ZDDesign.mediumGray)

            Text("No Documents")
                .font(.headline)
                .foregroundColor(ZDDesign.pureWhite)

            Text("Add PDFs to Documents/Library/")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding(.top, 60)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let chunk: TextChunk
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(ZDDesign.cyanAccent)

                    Text(chunk.docTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ZDDesign.cyanAccent)

                    Spacer()

                    Text("p.\(chunk.page)")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Text(chunk.content)
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
                    .lineLimit(3)

                HStack {
                    Text("Score: \(String(format: "%.2f", chunk.score))")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)

                    Spacer()

                    Text("Tap to open")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(12)
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: LibraryDocument
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(ZDDesign.cyanAccent)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ZDDesign.pureWhite)
                        .lineLimit(2)

                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Spacer()

                if document.isIndexed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ZDDesign.successGreen)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(ZDDesign.mediumGray)
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(12)
        }
    }
}

// MARK: - PDF Reader Sheet

struct PDFReaderSheet: View {
    let document: LibraryDocument
    let initialPage: Int?
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            Group {
                if let url = FastLibraryService.shared.pdfURL(for: document) {
                    PDFKitViewer(url: url, initialPage: initialPage ?? 1)
                } else {
                    Text("Unable to load PDF")
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - PDFKit Wrapper

struct PDFKitViewer: UIViewRepresentable {
    let url: URL
    let initialPage: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(ZDDesign.darkBackground)

        if let document = PDFDocument(url: url) {
            pdfView.document = document

            // Go to initial page
            if let page = document.page(at: initialPage - 1) {
                pdfView.go(to: page)
            }
        }

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}
