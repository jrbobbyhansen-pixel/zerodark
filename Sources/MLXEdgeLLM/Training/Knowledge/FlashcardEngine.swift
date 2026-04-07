import Foundation
import SwiftUI

// MARK: - Flashcard Model

struct Flashcard: Identifiable, Codable {
    let id: UUID
    let question: String
    let answer: String
    var nextReviewDate: Date
    var interval: TimeInterval
    var repetitions: Int
}

// MARK: - Flashcard Deck Model

struct FlashcardDeck: Identifiable, Codable {
    let id: UUID
    var name: String
    var flashcards: [Flashcard]
}

// MARK: - Flashcard Engine

class FlashcardEngine: ObservableObject {
    @Published var decks: [FlashcardDeck] = []
    
    init() {
        loadDecks()
    }
    
    func addDeck(_ deck: FlashcardDeck) {
        decks.append(deck)
        saveDecks()
    }
    
    func removeDeck(at index: Int) {
        decks.remove(at: index)
        saveDecks()
    }
    
    func addFlashcard(to deck: FlashcardDeck, flashcard: Flashcard) {
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index].flashcards.append(flashcard)
            saveDecks()
        }
    }
    
    func removeFlashcard(from deck: FlashcardDeck, at index: Int) {
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index].flashcards.remove(at: index)
            saveDecks()
        }
    }
    
    func reviewFlashcard(_ flashcard: Flashcard) {
        let newInterval = calculateNewInterval(for: flashcard)
        let newReviewDate = Date().addingTimeInterval(newInterval)
        
        if let deckIndex = decks.firstIndex(where: { $0.flashcards.contains { $0.id == flashcard.id } }),
           let flashcardIndex = decks[deckIndex].flashcards.firstIndex(where: { $0.id == flashcard.id }) {
            decks[deckIndex].flashcards[flashcardIndex].nextReviewDate = newReviewDate
            decks[deckIndex].flashcards[flashcardIndex].interval = newInterval
            decks[deckIndex].flashcards[flashcardIndex].repetitions += 1
            saveDecks()
        }
    }
    
    private func calculateNewInterval(for flashcard: Flashcard) -> TimeInterval {
        switch flashcard.repetitions {
        case 0:
            return 1 * 60 * 60 // 1 hour
        case 1:
            return 24 * 60 * 60 // 1 day
        case 2:
            return 7 * 24 * 60 * 60 // 7 days
        default:
            return flashcard.interval * 2 // Double the previous interval
        }
    }
    
    private func loadDecks() {
        if let data = UserDefaults.standard.data(forKey: "flashcardDecks"),
           let decodedDecks = try? JSONDecoder().decode([FlashcardDeck].self, from: data) {
            decks = decodedDecks
        }
    }
    
    private func saveDecks() {
        if let encodedDecks = try? JSONEncoder().encode(decks) {
            UserDefaults.standard.set(encodedDecks, forKey: "flashcardDecks")
        }
    }
}

// MARK: - Flashcard View Model

class FlashcardViewModel: ObservableObject {
    @Published var deck: FlashcardDeck
    @Published var currentFlashcard: Flashcard?
    @Published var isReviewing: Bool = false
    
    init(deck: FlashcardDeck) {
        self.deck = deck
        self.currentFlashcard = deck.flashcards.first { $0.nextReviewDate <= Date() }
    }
    
    func showNextFlashcard() {
        currentFlashcard = deck.flashcards.first { $0.nextReviewDate <= Date() }
    }
    
    func reviewFlashcard(correct: Bool) {
        if let currentFlashcard = currentFlashcard {
            let engine = FlashcardEngine()
            engine.reviewFlashcard(currentFlashcard)
            showNextFlashcard()
        }
    }
}

// MARK: - Flashcard View

struct FlashcardView: View {
    @StateObject private var viewModel: FlashcardViewModel
    
    init(deck: FlashcardDeck) {
        _viewModel = StateObject(wrappedValue: FlashcardViewModel(deck: deck))
    }
    
    var body: some View {
        VStack {
            if let currentFlashcard = viewModel.currentFlashcard {
                Text(currentFlashcard.question)
                    .font(.title)
                    .padding()
                
                if viewModel.isReviewing {
                    Text(currentFlashcard.answer)
                        .font(.body)
                        .padding()
                }
                
                Button(action: {
                    viewModel.reviewFlashcard(correct: true)
                }) {
                    Text("Correct")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.reviewFlashcard(correct: false)
                }) {
                    Text("Incorrect")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Text("No flashcards to review")
                    .font(.title)
                    .padding()
            }
        }
        .navigationTitle("Flashcard Review")
    }
}

// MARK: - Preview

struct FlashcardView_Previews: PreviewProvider {
    static var previews: some View {
        let deck = FlashcardDeck(id: UUID(), name: "Sample Deck", flashcards: [
            Flashcard(id: UUID(), question: "What is the capital of France?", answer: "Paris", nextReviewDate: Date(), interval: 0, repetitions: 0),
            Flashcard(id: UUID(), question: "What is 2 + 2?", answer: "4", nextReviewDate: Date(), interval: 0, repetitions: 0)
        ])
        FlashcardView(deck: deck)
    }
}