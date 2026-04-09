// ProtobufHelpers.swift — Minimal protobuf encoding/decoding utilities
// Shared by MeshtasticBridge and MeshRelay for wire-format parsing
// No external protobuf library — manual varint/field handling

import Foundation

// MARK: - Protobuf Decoding

/// Read a varint from a byte array at the given offset
/// Returns (value, bytesConsumed) or nil if malformed
func pbReadVarint(_ bytes: [UInt8], offset: Int) -> (UInt64, Int)? {
    var result: UInt64 = 0
    var shift = 0
    var i = offset
    while i < bytes.count {
        let byte = bytes[i]
        i += 1
        result |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 { return (result, i - offset) }
        shift += 7
        if shift >= 64 { return nil }
    }
    return nil
}

/// Read a protobuf field header (tag + wire type)
/// Returns (fieldTag, wireType, headerLength) or nil if malformed
func pbReadFieldHeader(_ bytes: [UInt8], offset: Int) -> (tag: Int, wireType: Int, headerLen: Int)? {
    guard let (v, n) = pbReadVarint(bytes, offset: offset) else { return nil }
    return (Int(v >> 3), Int(v & 0x07), n)
}

/// Skip an unknown protobuf field based on wire type
/// Returns bytes consumed, or nil if malformed
func pbSkipField(_ bytes: [UInt8], offset: Int, wireType: Int) -> Int? {
    switch wireType {
    case 0: // Varint
        guard let (_, n) = pbReadVarint(bytes, offset: offset) else { return nil }
        return n
    case 1: // 64-bit fixed
        return offset + 8 <= bytes.count ? 8 : nil
    case 2: // Length-delimited
        guard let (length, lenBytes) = pbReadVarint(bytes, offset: offset) else { return nil }
        let total = lenBytes + Int(length)
        return offset + total <= bytes.count ? total : nil
    case 5: // 32-bit fixed
        return offset + 4 <= bytes.count ? 4 : nil
    default:
        return nil
    }
}

// MARK: - Protobuf Encoding

/// Encode a UInt64 as a varint
func pbEncodeVarint(_ value: UInt64) -> Data {
    var data = Data()
    var v = value
    repeat {
        var byte = UInt8(v & 0x7F)
        v >>= 7
        if v != 0 { byte |= 0x80 }
        data.append(byte)
    } while v != 0
    return data
}

/// Encode a protobuf field with tag, wire type, and length-delimited value
func pbEncodeField(tag: Int, wireType: Int, value: Data) -> Data {
    var data = Data()
    data.append(contentsOf: pbEncodeVarint(UInt64(tag << 3 | wireType)))
    if wireType == 2 {
        // Length-delimited: prepend length
        data.append(contentsOf: pbEncodeVarint(UInt64(value.count)))
    }
    data.append(value)
    return data
}

/// Encode a varint field (tag + varint value)
func pbEncodeVarintField(tag: Int, value: UInt64) -> Data {
    var data = Data()
    data.append(contentsOf: pbEncodeVarint(UInt64(tag << 3 | 0))) // wireType 0
    data.append(contentsOf: pbEncodeVarint(value))
    return data
}

/// Encode a length-delimited field (tag + bytes)
func pbEncodeBytesField(tag: Int, value: Data) -> Data {
    pbEncodeField(tag: tag, wireType: 2, value: value)
}

/// Encode a string field
func pbEncodeStringField(tag: Int, value: String) -> Data {
    pbEncodeBytesField(tag: tag, value: Data(value.utf8))
}
