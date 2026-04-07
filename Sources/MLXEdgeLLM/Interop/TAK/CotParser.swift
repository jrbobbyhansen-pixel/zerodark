import Foundation
import CoreLocation

struct CotMessage {
    let position: CLLocationCoordinate2D
    let type: String
    let remarks: String
}

class CotParser {
    func parse(_ message: String) -> CotMessage? {
        guard let data = message.data(using: .utf8) else {
            return nil
        }
        
        do {
            if let cotDict = try XMLParser(data: data).parse() as? [String: Any],
               let positionDict = cotDict["position"] as? [String: Any],
               let latitude = positionDict["latitude"] as? Double,
               let longitude = positionDict["longitude"] as? Double,
               let type = cotDict["type"] as? String,
               let remarks = cotDict["remarks"] as? String {
                
                let position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                return CotMessage(position: position, type: type, remarks: remarks)
            }
        } catch {
            print("Error parsing CoT message: \(error)")
        }
        
        return nil
    }
}

extension XMLParser {
    func parse() throws -> Any? {
        var result: Any?
        let parser = XMLParser(data: self.data)
        let parserDelegate = XMLParserDelegate()
        parser.delegate = parserDelegate
        parser.parse()
        result = parserDelegate.parsedResult
        return result
    }
}

class XMLParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var parsedResult: Any?
    private var currentData = ""
    private var stack: [String: Any] = [:]
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentData = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentData.append(string)
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let value = currentData.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            if let existingDict = stack[elementName] as? [String: Any] {
                stack[elementName] = [elementName: value].merging(existingDict) { (_, last) in last }
            } else {
                stack[elementName] = [elementName: value]
            }
        }
        
        if elementName == "cot" {
            parsedResult = stack
        }
    }
}