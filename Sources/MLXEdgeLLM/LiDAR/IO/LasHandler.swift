import Foundation
import Compression

// MARK: - LAS/LAZ File Handler

struct LasHeader {
    var fileSignature: UInt32
    var fileSourceID: UInt16
    var globalEncoding: UInt16
    var projectIDGUID1: UInt32
    var projectIDGUID2: UInt32
    var projectIDGUID3: UInt32
    var projectIDGUID4: UInt32
    var versionMajor: UInt8
    var versionMinor: UInt8
    var systemIdentifier: String
    var generatingSoftware: String
    var fileCreationDayOfYear: UInt16
    var fileCreationYear: UInt16
    var headerSize: UInt16
    var offsetToPointData: UInt32
    var numberOfVariableLengthRecords: UInt32
    var pointDataFormatID: UInt8
    var pointDataRecordLength: UInt16
    var numberOfPoints: UInt32
    var numberOfPointsByReturn: [UInt32]
    var xScaleFactor: Double
    var yScaleFactor: Double
    var zScaleFactor: Double
    var xOffset: Double
    var yOffset: Double
    var zOffset: Double
    var maxX: Double
    var minX: Double
    var maxY: Double
    var minY: Double
    var maxZ: Double
    var minZ: Double
}

struct LasPoint {
    var x: Double
    var y: Double
    var z: Double
    var intensity: UInt16
    var returnNumber: UInt8
    var numberOfReturns: UInt8
    var scanDirectionFlag: UInt8
    var edgeOfFlightLine: UInt8
    var classification: UInt8
    var scanAngleRank: Int8
    var userData: UInt8
    var pointSourceID: UInt16
}

class LasHandler {
    func readLasFile(from url: URL) throws -> (header: LasHeader, points: [LasPoint]) {
        let data = try Data(contentsOf: url)
        var offset = 0
        
        // Read header
        var header = LasHeader(
            fileSignature: data.readUInt32(from: &offset),
            fileSourceID: data.readUInt16(from: &offset),
            globalEncoding: data.readUInt16(from: &offset),
            projectIDGUID1: data.readUInt32(from: &offset),
            projectIDGUID2: data.readUInt32(from: &offset),
            projectIDGUID3: data.readUInt32(from: &offset),
            projectIDGUID4: data.readUInt32(from: &offset),
            versionMajor: data.readUInt8(from: &offset),
            versionMinor: data.readUInt8(from: &offset),
            systemIdentifier: data.readString(from: &offset, length: 32),
            generatingSoftware: data.readString(from: &offset, length: 32),
            fileCreationDayOfYear: data.readUInt16(from: &offset),
            fileCreationYear: data.readUInt16(from: &offset),
            headerSize: data.readUInt16(from: &offset),
            offsetToPointData: data.readUInt32(from: &offset),
            numberOfVariableLengthRecords: data.readUInt32(from: &offset),
            pointDataFormatID: data.readUInt8(from: &offset),
            pointDataRecordLength: data.readUInt16(from: &offset),
            numberOfPoints: data.readUInt32(from: &offset),
            numberOfPointsByReturn: [data.readUInt32(from: &offset), data.readUInt32(from: &offset), data.readUInt32(from: &offset), data.readUInt32(from: &offset), data.readUInt32(from: &offset)],
            xScaleFactor: data.readDouble(from: &offset),
            yScaleFactor: data.readDouble(from: &offset),
            zScaleFactor: data.readDouble(from: &offset),
            xOffset: data.readDouble(from: &offset),
            yOffset: data.readDouble(from: &offset),
            zOffset: data.readDouble(from: &offset),
            maxX: data.readDouble(from: &offset),
            minX: data.readDouble(from: &offset),
            maxY: data.readDouble(from: &offset),
            minY: data.readDouble(from: &offset),
            maxZ: data.readDouble(from: &offset),
            minZ: data.readDouble(from: &offset)
        )
        
        // Read points
        var points: [LasPoint] = []
        offset = Int(header.offsetToPointData)
        for _ in 0..<header.numberOfPoints {
            let point = LasPoint(
                x: (data.readDouble(from: &offset) + header.xOffset) * header.xScaleFactor,
                y: (data.readDouble(from: &offset) + header.yOffset) * header.yScaleFactor,
                z: (data.readDouble(from: &offset) + header.zOffset) * header.zScaleFactor,
                intensity: data.readUInt16(from: &offset),
                returnNumber: data.readUInt8(from: &offset),
                numberOfReturns: data.readUInt8(from: &offset),
                scanDirectionFlag: data.readUInt8(from: &offset),
                edgeOfFlightLine: data.readUInt8(from: &offset),
                classification: data.readUInt8(from: &offset),
                scanAngleRank: data.readInt8(from: &offset),
                userData: data.readUInt8(from: &offset),
                pointSourceID: data.readUInt16(from: &offset)
            )
            points.append(point)
        }
        
        return (header, points)
    }
    
    func writeLasFile(to url: URL, header: LasHeader, points: [LasPoint]) throws {
        var data = Data()
        
        // Write header
        data.append(header.fileSignature.data)
        data.append(header.fileSourceID.data)
        data.append(header.globalEncoding.data)
        data.append(header.projectIDGUID1.data)
        data.append(header.projectIDGUID2.data)
        data.append(header.projectIDGUID3.data)
        data.append(header.projectIDGUID4.data)
        data.append(header.versionMajor.data)
        data.append(header.versionMinor.data)
        data.append(header.systemIdentifier.data)
        data.append(header.generatingSoftware.data)
        data.append(header.fileCreationDayOfYear.data)
        data.append(header.fileCreationYear.data)
        data.append(header.headerSize.data)
        data.append(header.offsetToPointData.data)
        data.append(header.numberOfVariableLengthRecords.data)
        data.append(header.pointDataFormatID.data)
        data.append(header.pointDataRecordLength.data)
        data.append(header.numberOfPoints.data)
        for pointCount in header.numberOfPointsByReturn {
            data.append(pointCount.data)
        }
        data.append(header.xScaleFactor.data)
        data.append(header.yScaleFactor.data)
        data.append(header.zScaleFactor.data)
        data.append(header.xOffset.data)
        data.append(header.yOffset.data)
        data.append(header.zOffset.data)
        data.append(header.maxX.data)
        data.append(header.minX.data)
        data.append(header.maxY.data)
        data.append(header.minY.data)
        data.append(header.maxZ.data)
        data.append(header.minZ.data)
        
        // Write points
        for point in points {
            data.append((point.x / header.xScaleFactor - header.xOffset).data)
            data.append((point.y / header.yScaleFactor - header.yOffset).data)
            data.append((point.z / header.zScaleFactor - header.zOffset).data)
            data.append(point.intensity.data)
            data.append(point.returnNumber.data)
            data.append(point.numberOfReturns.data)
            data.append(point.scanDirectionFlag.data)
            data.append(point.edgeOfFlightLine.data)
            data.append(point.classification.data)
            data.append(point.scanAngleRank.data)
            data.append(point.userData.data)
            data.append(point.pointSourceID.data)
        }
        
        try data.write(to: url)
    }
    
    func readLaszFile(from url: URL) throws -> (header: LasHeader, points: [LasPoint]) {
        let compressedData = try Data(contentsOf: url)
        let decompressedData = try decompress(data: compressedData)
        return try readLasFile(from: URL(fileURLWithPath: ""))
    }
    
    func writeLaszFile(to url: URL, header: LasHeader, points: [LasPoint]) throws {
        let data = try writeLasFile(to: URL(fileURLWithPath: ""), header: header, points: points)
        let compressedData = try compress(data: data)
        try compressedData.write(to: url)
    }
    
    private func decompress(data: Data) throws -> Data {
        var decompressedData = Data()
        var bufferSize: Int = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var stream = compression_stream()
        compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZ4)
        
        let sourceBuffer = data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let sourceSize = data.count
        
        var sourceBytesRead = 0
        var status: compression_status
        
        repeat {
            stream.src_ptr = sourceBuffer.advanced(by: sourceBytesRead)
            stream.src_size = sourceSize - sourceBytesRead
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            
            status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE)
            
            if status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END {
                decompressedData.append(buffer, count: Int(stream.dst_ptr - buffer))
            }
            
            sourceBytesRead += Int(stream.src_ptr - sourceBuffer)
        } while status == COMPRESSION_STATUS_OK
        
        compression_stream_destroy(&stream)
        
        if status != COMPRESSION_STATUS_END {
            throw NSError(domain: "Decompression failed", code: Int(status), userInfo: nil)
        }
        
        return decompressedData
    }
    
    private func compress(data: Data) throws -> Data {
        var compressedData = Data()
        var bufferSize: Int = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var stream = compression_stream()
        compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZ4)
        
        let sourceBuffer = data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let sourceSize = data.count
        
        var sourceBytesRead = 0
        var status: compression_status
        
        repeat {
            stream.src_ptr = sourceBuffer.advanced(by: sourceBytesRead)
            stream.src_size = sourceSize - sourceBytesRead
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            
            status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE)
            
            if status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END {
                compressedData.append(buffer, count: Int(stream.dst_ptr - buffer))
            }
            
            sourceBytesRead += Int(stream.src_ptr - sourceBuffer)
        } while status == COMPRESSION_STATUS_OK
        
        compression_stream_destroy(&stream)
        
        if status != COMPRESSION_STATUS_END {
            throw NSError(domain: "Compression failed", code: Int(status), userInfo: nil)
        }
        
        return compressedData
    }
}

extension Data {
    func readUInt32(from offset: inout Int) -> UInt32 {
        let value = self[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4
        return value
    }
    
    func readUInt16(from offset: inout Int) -> UInt16 {
        let value = self[offset..<(offset + 2)].withUnsafeBytes { $0.load(as: UInt16.self) }
        offset += 2
        return value
    }
    
    func readUInt8(from offset: inout Int) -> UInt8 {
        let value = self[offset]
        offset += 1
        return value
    }
    
    func readInt8(from offset: inout Int) -> Int8 {
        let value = Int8(self[offset])
        offset += 1
        return value
    }
    
    func readString(from offset: inout Int, length: Int) -> String {
        let value = String(data: self[offset..<(offset + length)], encoding: .ascii) ?? ""
        offset += length
        return value
    }
    
    func readDouble(from offset: inout Int) -> Double {
        let value = self[offset..<(offset + 8)].withUnsafeBytes { $0.load(as: Double.self) }
        offset += 8
        return value
    }
}

extension UInt32 {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt16 {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt8 {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension Int8 {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension Double {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}