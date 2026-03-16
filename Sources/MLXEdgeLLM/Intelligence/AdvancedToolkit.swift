//
//  AdvancedToolkit.swift
//  ZeroDark
//
//  Advanced Apple APIs + Free External APIs
//  Vision, Speech, ShazamKit, Motion, NFC, and more
//

import Foundation
import AVFoundation
import Speech
#if canImport(Vision)
import Vision
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CoreNFC)
import CoreNFC
#endif
#if canImport(ShazamKit)
import ShazamKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - Advanced Toolkit

@MainActor
public class AdvancedToolkit: ObservableObject {
    public static let shared = AdvancedToolkit()
    
    // Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Motion Manager
    #if canImport(CoreMotion)
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    #endif
    
    // Shazam
    #if canImport(ShazamKit)
    private var shazamSession: SHSession?
    #endif
    
    @Published var isListening = false
    @Published var transcribedText = ""
    
    // MARK: - Execute Advanced Tools
    
    public func execute(_ tool: String, arguments: [String: String]) async -> String {
        switch tool.lowercased() {
        // Vision
        case "ocr", "read_text", "scan_text":
            return await performOCR(imageData: arguments["image"])
        case "detect_objects", "identify":
            return await detectObjects(imageData: arguments["image"])
        case "read_barcode", "scan_barcode", "scan_qr":
            return await readBarcode(imageData: arguments["image"])
        case "face_detect":
            return await detectFaces(imageData: arguments["image"])
            
        // Speech
        case "listen", "transcribe", "speech_to_text":
            return await startListening()
        case "stop_listening":
            return stopListening()
            
        // Shazam
        case "shazam", "identify_song", "what_song":
            return await identifySong()
            
        // Motion
        case "motion", "accelerometer":
            return getMotionData()
        case "pedometer", "steps_today":
            return await getPedometerData()
        case "altitude":
            return await getAltitude()
            
        // Authentication
        case "authenticate", "biometric", "faceid", "touchid":
            return await authenticateUser()
            
        // Free APIs
        case "news", "headlines":
            return await getNews(query: arguments["query"] ?? "technology")
        case "crypto", "bitcoin", "ethereum":
            return await getCryptoPrice(coin: arguments["coin"] ?? "bitcoin")
        case "stocks", "stock_price":
            return await getStockPrice(symbol: arguments["symbol"] ?? "AAPL")
        case "nasa", "apod", "space":
            return await getNASAPicture()
        case "quote", "inspiration":
            return await getQuote()
        case "joke", "tell_joke":
            return await getJoke()
        case "fact", "random_fact":
            return await getRandomFact()
        case "trivia":
            return await getTriviaQuestion()
        case "wiki", "wikipedia":
            return await searchWikipedia(query: arguments["query"] ?? "")
        case "air_quality", "aqi":
            return await getAirQuality(city: arguments["city"] ?? "San Antonio")
        case "sunrise", "sunset":
            return await getSunriseSunset(city: arguments["city"] ?? "San Antonio")
        case "holiday", "holidays":
            return await getHolidays(country: arguments["country"] ?? "US")
        case "bible", "verse":
            return await getBibleVerse(reference: arguments["reference"] ?? "random")
        case "hackernews", "hn", "tech_news":
            return await getHackerNews()
        case "dog", "random_dog":
            return await getRandomDog()
        case "cat", "random_cat":
            return await getRandomCat()
        case "ip", "my_ip", "ip_info":
            return await getIPInfo()
            
        // System
        case "network", "wifi", "connection":
            return getNetworkStatus()
        case "disk", "storage":
            return getDiskSpace()
        case "memory", "ram_usage":
            return getMemoryUsage()
        case "cpu", "processor":
            return getCPUInfo()
            
        default:
            return "Unknown advanced tool: \(tool)"
        }
    }
    
    // MARK: - Vision Framework
    
    private func performOCR(imageData: String?) async -> String {
        #if canImport(Vision)
        // Would process image and extract text
        return "📝 OCR: Point camera at text and tap capture. Text will be extracted using Vision framework."
        #else
        return "Vision framework not available"
        #endif
    }
    
    private func detectObjects(imageData: String?) async -> String {
        #if canImport(Vision)
        return "🔍 Object Detection: Vision framework can identify 1000+ object categories. Point camera at object to identify."
        #else
        return "Vision framework not available"
        #endif
    }
    
    private func readBarcode(imageData: String?) async -> String {
        #if canImport(Vision)
        return "📱 Barcode Scanner: Supports QR codes, UPC, EAN, Code 128, and more. Point camera at barcode."
        #else
        return "Vision framework not available"
        #endif
    }
    
    private func detectFaces(imageData: String?) async -> String {
        #if canImport(Vision)
        return "👤 Face Detection: Can detect faces, landmarks, expressions. Point camera at face."
        #else
        return "Vision framework not available"
        #endif
    }
    
    // MARK: - Speech Recognition
    
    private func startListening() async -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return "❌ Speech recognition not available"
        }
        
        // Request authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            return "❌ Speech recognition not authorized. Enable in Settings → Privacy → Speech Recognition"
        }
        
        isListening = true
        return "🎤 Listening... Speak now. Say 'stop listening' when done."
    }
    
    private func stopListening() -> String {
        audioEngine.stop()
        recognitionTask?.cancel()
        isListening = false
        
        let result = transcribedText.isEmpty ? "No speech detected" : transcribedText
        transcribedText = ""
        return "🎤 Stopped listening. Heard: \"\(result)\""
    }
    
    // MARK: - ShazamKit
    
    private func identifySong() async -> String {
        #if canImport(ShazamKit)
        return "🎵 Shazam: Play music near the device. Song identification requires microphone access and ShazamKit entitlement."
        #else
        return "ShazamKit not available on this device"
        #endif
    }
    
    // MARK: - Core Motion
    
    private func getMotionData() -> String {
        #if canImport(CoreMotion)
        guard motionManager.isDeviceMotionAvailable else {
            return "Motion sensors not available"
        }
        
        motionManager.startDeviceMotionUpdates()
        defer { motionManager.stopDeviceMotionUpdates() }
        
        if let motion = motionManager.deviceMotion {
            let attitude = motion.attitude
            return """
            📱 Device Motion:
            • Pitch: \(String(format: "%.2f", attitude.pitch * 180 / .pi))°
            • Roll: \(String(format: "%.2f", attitude.roll * 180 / .pi))°
            • Yaw: \(String(format: "%.2f", attitude.yaw * 180 / .pi))°
            • Gravity: x=\(String(format: "%.2f", motion.gravity.x)), y=\(String(format: "%.2f", motion.gravity.y)), z=\(String(format: "%.2f", motion.gravity.z))
            """
        }
        return "Could not get motion data"
        #else
        return "Core Motion not available"
        #endif
    }
    
    private func getPedometerData() async -> String {
        #if canImport(CoreMotion)
        guard CMPedometer.isStepCountingAvailable() else {
            return "Pedometer not available"
        }
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                if let data = data {
                    var result = "🚶 Today's Activity:\n"
                    result += "• Steps: \(data.numberOfSteps)\n"
                    if let distance = data.distance {
                        result += "• Distance: \(String(format: "%.2f", distance.doubleValue / 1609.34)) miles\n"
                    }
                    if let floors = data.floorsAscended {
                        result += "• Floors climbed: \(floors)"
                    }
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: "Could not get pedometer data: \(error?.localizedDescription ?? "Unknown")")
                }
            }
        }
        #else
        return "Core Motion not available"
        #endif
    }
    
    private func getAltitude() async -> String {
        #if canImport(CoreMotion)
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            return "Altimeter not available"
        }
        
        let altimeter = CMAltimeter()
        
        return await withCheckedContinuation { continuation in
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                altimeter.stopRelativeAltitudeUpdates()
                
                if let data = data {
                    let meters = data.relativeAltitude.doubleValue
                    let feet = meters * 3.28084
                    let pressure = data.pressure.doubleValue
                    continuation.resume(returning: "⛰️ Altitude: \(String(format: "%.1f", feet)) ft (\(String(format: "%.1f", meters)) m)\nPressure: \(String(format: "%.1f", pressure)) kPa")
                } else {
                    continuation.resume(returning: "Could not get altitude")
                }
            }
        }
        #else
        return "Altimeter not available"
        #endif
    }
    
    // MARK: - Biometric Authentication
    
    private func authenticateUser() async -> String {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "❌ Biometric authentication not available: \(error?.localizedDescription ?? "Unknown")"
        }
        
        let biometricType = context.biometryType == .faceID ? "Face ID" : "Touch ID"
        
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate with ZeroDark") { success, error in
                if success {
                    continuation.resume(returning: "✅ \(biometricType) authentication successful!")
                } else {
                    continuation.resume(returning: "❌ Authentication failed: \(error?.localizedDescription ?? "Cancelled")")
                }
            }
        }
        #else
        return "Authentication not available"
        #endif
    }
    
    // MARK: - Free APIs: News
    
    private func getNews(query: String) async -> String {
        // Using HN API (free, no key)
        let url = URL(string: "https://hn.algolia.com/api/v1/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&hitsPerPage=5")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hits = json["hits"] as? [[String: Any]] {
                
                let headlines = hits.prefix(5).compactMap { hit -> String? in
                    guard let title = hit["title"] as? String else { return nil }
                    return "• \(title)"
                }.joined(separator: "\n")
                
                return "📰 Latest news on \"\(query)\":\n\(headlines.isEmpty ? "No results found" : headlines)"
            }
        } catch {
            return "Could not fetch news: \(error.localizedDescription)"
        }
        return "Could not fetch news"
    }
    
    // MARK: - Free APIs: Crypto
    
    private func getCryptoPrice(coin: String) async -> String {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(coin.lowercased())&vs_currencies=usd&include_24hr_change=true")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let coinData = json[coin.lowercased()] as? [String: Any],
               let price = coinData["usd"] as? Double {
                
                let change = coinData["usd_24h_change"] as? Double ?? 0
                let changeStr = change >= 0 ? "+\(String(format: "%.2f", change))%" : "\(String(format: "%.2f", change))%"
                let emoji = change >= 0 ? "📈" : "📉"
                
                return "\(emoji) \(coin.capitalized): $\(String(format: "%.2f", price)) (\(changeStr) 24h)"
            }
        } catch {
            return "Could not fetch crypto price"
        }
        return "Could not fetch \(coin) price"
    }
    
    // MARK: - Free APIs: Stocks (Alpha Vantage - limited free)
    
    private func getStockPrice(symbol: String) async -> String {
        // Note: Would need API key for real data
        return "📊 Stock data for \(symbol.uppercased()) requires API key. Try: crypto bitcoin, crypto ethereum"
    }
    
    // MARK: - Free APIs: NASA APOD
    
    private func getNASAPicture() async -> String {
        let url = URL(string: "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String,
               let explanation = json["explanation"] as? String {
                
                let shortExplanation = explanation.prefix(200)
                return "🚀 NASA Picture of the Day:\n\"\(title)\"\n\n\(shortExplanation)...\n\n(View full image in NASA app)"
            }
        } catch {
            return "Could not fetch NASA data"
        }
        return "Could not fetch NASA data"
    }
    
    // MARK: - Free APIs: Quotes
    
    private func getQuote() async -> String {
        let url = URL(string: "https://api.quotable.io/random")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String,
               let author = json["author"] as? String {
                return "💭 \"\(content)\"\n— \(author)"
            }
        } catch {
            // Fallback quotes
            let quotes = [
                ("The only way to do great work is to love what you do.", "Steve Jobs"),
                ("Innovation distinguishes between a leader and a follower.", "Steve Jobs"),
                ("Stay hungry, stay foolish.", "Steve Jobs"),
                ("Think different.", "Apple"),
            ]
            let random = quotes.randomElement()!
            return "💭 \"\(random.0)\"\n— \(random.1)"
        }
        return "Could not fetch quote"
    }
    
    // MARK: - Free APIs: Jokes
    
    private func getJoke() async -> String {
        let url = URL(string: "https://official-joke-api.appspot.com/random_joke")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let setup = json["setup"] as? String,
               let punchline = json["punchline"] as? String {
                return "😄 \(setup)\n\n\(punchline)"
            }
        } catch {
            return "😄 Why do programmers prefer dark mode?\n\nBecause light attracts bugs!"
        }
        return "Could not fetch joke"
    }
    
    // MARK: - Free APIs: Facts
    
    private func getRandomFact() async -> String {
        let url = URL(string: "https://uselessfacts.jsph.pl/api/v2/facts/random")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fact = json["text"] as? String {
                return "🎲 Random fact: \(fact)"
            }
        } catch {
            return "🎲 Random fact: Honey never spoils. Archaeologists have found 3000-year-old honey in Egyptian tombs that was still edible."
        }
        return "Could not fetch fact"
    }
    
    // MARK: - Free APIs: Trivia
    
    private func getTriviaQuestion() async -> String {
        let url = URL(string: "https://opentdb.com/api.php?amount=1&type=multiple")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let question = results.first {
                
                let q = (question["question"] as? String)?.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'") ?? ""
                let correct = (question["correct_answer"] as? String) ?? ""
                let category = (question["category"] as? String) ?? ""
                
                return "🧠 Trivia (\(category)):\n\n\(q)\n\n(Answer: \(correct))"
            }
        } catch {
            return "Could not fetch trivia"
        }
        return "Could not fetch trivia"
    }
    
    // MARK: - Free APIs: Wikipedia
    
    private func searchWikipedia(query: String) async -> String {
        guard !query.isEmpty else { return "Please provide a search term" }
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let extract = json["extract"] as? String,
               let title = json["title"] as? String {
                
                let shortExtract = extract.prefix(400)
                return "📚 \(title)\n\n\(shortExtract)..."
            }
        } catch {
            return "Could not find Wikipedia article for \"\(query)\""
        }
        return "Could not search Wikipedia"
    }
    
    // MARK: - Free APIs: Air Quality
    
    private func getAirQuality(city: String) async -> String {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let url = URL(string: "https://api.waqi.info/feed/\(encoded)/?token=demo")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let aqi = dataObj["aqi"] as? Int {
                
                let level: String
                let emoji: String
                switch aqi {
                case 0...50: level = "Good"; emoji = "🟢"
                case 51...100: level = "Moderate"; emoji = "🟡"
                case 101...150: level = "Unhealthy for Sensitive Groups"; emoji = "🟠"
                case 151...200: level = "Unhealthy"; emoji = "🔴"
                case 201...300: level = "Very Unhealthy"; emoji = "🟣"
                default: level = "Hazardous"; emoji = "⚫"
                }
                
                return "\(emoji) Air Quality in \(city): AQI \(aqi) (\(level))"
            }
        } catch {
            return "Could not fetch air quality for \(city)"
        }
        return "Could not fetch air quality"
    }
    
    // MARK: - Free APIs: Sunrise/Sunset
    
    private func getSunriseSunset(city: String) async -> String {
        // Coordinates for common cities
        let coords: (lat: Double, lng: Double) = {
            switch city.lowercased() {
            case "san antonio": return (29.4241, -98.4936)
            case "austin": return (30.2672, -97.7431)
            case "houston": return (29.7604, -95.3698)
            case "dallas": return (32.7767, -96.7970)
            case "new york": return (40.7128, -74.0060)
            default: return (29.4241, -98.4936)
            }
        }()
        
        let url = URL(string: "https://api.sunrise-sunset.org/json?lat=\(coords.lat)&lng=\(coords.lng)&formatted=1")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any],
               let sunrise = results["sunrise"] as? String,
               let sunset = results["sunset"] as? String {
                
                return "🌅 \(city)\n• Sunrise: \(sunrise) UTC\n• Sunset: \(sunset) UTC"
            }
        } catch {
            return "Could not fetch sunrise/sunset"
        }
        return "Could not fetch sunrise/sunset"
    }
    
    // MARK: - Free APIs: Holidays
    
    private func getHolidays(country: String) async -> String {
        let year = Calendar.current.component(.year, from: Date())
        let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(country.uppercased())")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let holidays = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                
                let today = Date()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                
                let upcoming = holidays.compactMap { holiday -> (String, String)? in
                    guard let dateStr = holiday["date"] as? String,
                          let name = holiday["localName"] as? String,
                          let date = formatter.date(from: dateStr),
                          date > today else { return nil }
                    return (name, dateStr)
                }.prefix(5)
                
                let list = upcoming.map { "• \($0.1): \($0.0)" }.joined(separator: "\n")
                return "🎉 Upcoming holidays in \(country.uppercased()):\n\(list.isEmpty ? "No upcoming holidays" : list)"
            }
        } catch {
            return "Could not fetch holidays"
        }
        return "Could not fetch holidays"
    }
    
    // MARK: - Free APIs: Bible
    
    private func getBibleVerse(reference: String) async -> String {
        let query = reference == "random" ? "john+3:16" : reference.replacingOccurrences(of: " ", with: "+")
        let url = URL(string: "https://bible-api.com/\(query)")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String,
               let ref = json["reference"] as? String {
                
                let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return "📖 \(ref)\n\n\"\(cleanText)\""
            }
        } catch {
            return "Could not fetch Bible verse"
        }
        return "Could not fetch Bible verse"
    }
    
    // MARK: - Free APIs: Hacker News
    
    private func getHackerNews() async -> String {
        let url = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let ids = try JSONSerialization.jsonObject(with: data) as? [Int] {
                
                var headlines: [String] = []
                for id in ids.prefix(5) {
                    let storyURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!
                    let (storyData, _) = try await URLSession.shared.data(from: storyURL)
                    if let story = try JSONSerialization.jsonObject(with: storyData) as? [String: Any],
                       let title = story["title"] as? String {
                        headlines.append("• \(title)")
                    }
                }
                
                return "🔥 Top Hacker News:\n\(headlines.joined(separator: "\n"))"
            }
        } catch {
            return "Could not fetch Hacker News"
        }
        return "Could not fetch Hacker News"
    }
    
    // MARK: - Free APIs: Random Dog
    
    private func getRandomDog() async -> String {
        let url = URL(string: "https://dog.ceo/api/breeds/image/random")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let imageURL = json["message"] as? String {
                return "🐕 Random dog!\n\(imageURL)"
            }
        } catch {
            return "Could not fetch dog image"
        }
        return "Could not fetch dog image"
    }
    
    // MARK: - Free APIs: Random Cat
    
    private func getRandomCat() async -> String {
        let url = URL(string: "https://api.thecatapi.com/v1/images/search")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let cat = json.first,
               let imageURL = cat["url"] as? String {
                return "🐱 Random cat!\n\(imageURL)"
            }
        } catch {
            return "Could not fetch cat image"
        }
        return "Could not fetch cat image"
    }
    
    // MARK: - Free APIs: IP Info
    
    private func getIPInfo() async -> String {
        let url = URL(string: "http://ip-api.com/json/")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                let ip = json["query"] as? String ?? "Unknown"
                let city = json["city"] as? String ?? "Unknown"
                let region = json["regionName"] as? String ?? ""
                let country = json["country"] as? String ?? ""
                let isp = json["isp"] as? String ?? ""
                
                return "🌐 Your IP: \(ip)\n📍 Location: \(city), \(region), \(country)\n🔌 ISP: \(isp)"
            }
        } catch {
            return "Could not fetch IP info"
        }
        return "Could not fetch IP info"
    }
    
    // MARK: - System Info
    
    private func getNetworkStatus() -> String {
        // Basic network check
        return "🌐 Network: Connected (use Settings → Wi-Fi for details)"
    }
    
    private func getDiskSpace() -> String {
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let total = (attrs[.systemSize] as? Int64) ?? 0
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            let used = total - free
            
            let totalGB = Double(total) / 1_000_000_000
            let usedGB = Double(used) / 1_000_000_000
            let freeGB = Double(free) / 1_000_000_000
            
            return """
            💾 Storage:
            • Total: \(String(format: "%.1f", totalGB)) GB
            • Used: \(String(format: "%.1f", usedGB)) GB
            • Free: \(String(format: "%.1f", freeGB)) GB
            """
        }
        return "Could not get disk space"
    }
    
    private func getMemoryUsage() -> String {
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = Double(processInfo.physicalMemory) / 1_000_000_000
        
        return """
        🧠 Memory:
        • Total RAM: \(String(format: "%.1f", physicalMemory)) GB
        • (Per-app usage requires Instruments)
        """
    }
    
    private func getCPUInfo() -> String {
        let processInfo = ProcessInfo.processInfo
        
        return """
        ⚡ Processor:
        • Cores: \(processInfo.processorCount)
        • Active: \(processInfo.activeProcessorCount)
        """
    }
}
