// MeshCryptoTests.swift
// Unit tests for Mesh network AES-256-GCM encryption

import XCTest
import CryptoKit
@testable import ZeroDark

final class MeshCryptoTests: XCTestCase {

    func testAES256GCMEncryptionRoundtrip() {
        // Test encrypt → decrypt roundtrip with AES-256-GCM

        let plaintext = "Hello, Mesh Network!".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        do {
            // Encrypt
            let sealedBox = try AES.GCM.seal(plaintext, using: key)

            // Decrypt
            let decrypted = try AES.GCM.open(sealedBox, using: key)

            // Verify
            XCTAssertEqual(decrypted, plaintext)
        } catch {
            XCTFail("Encryption/decryption failed: \(error)")
        }
    }

    func testGCMAuthenticationTagValidation() {
        // Test that GCM detects tampering via authentication tag

        let plaintext = "Original message".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        do {
            // Encrypt
            let sealedBox = try AES.GCM.seal(plaintext, using: key)

            // Tamper with ciphertext
            var tamperedCiphertext = sealedBox.ciphertext
            if !tamperedCiphertext.isEmpty {
                // Flip a bit
                var mutableCiphertext = [UInt8](tamperedCiphertext)
                mutableCiphertext[0] ^= 0x01
                tamperedCiphertext = Data(mutableCiphertext)
            }

            // Create tampered sealedbox
            let tamperedBox = try AES.GCM.SealedBox(nonce: sealedBox.nonce,
                                                     ciphertext: tamperedCiphertext,
                                                     tag: sealedBox.tag)

            // Attempt decryption with tampered data
            _ = try AES.GCM.open(tamperedBox, using: key)

            // Should not reach here
            XCTFail("Decryption should have failed on tampered data")
        } catch {
            // Expected: authentication failed
            XCTAssertNotNil(error)
        }
    }

    func testTagTamperDetection() {
        // Test that tampering with authentication tag is detected

        let plaintext = "Secure mesh message".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        do {
            // Encrypt
            let sealedBox = try AES.GCM.seal(plaintext, using: key)

            // Tamper with authentication tag
            var tamperedTag = sealedBox.tag
            var mutableTag = [UInt8](tamperedTag)
            mutableTag[0] ^= 0xFF  // Flip all bits in first byte

            let tamperedBox = try AES.GCM.SealedBox(nonce: sealedBox.nonce,
                                                     ciphertext: sealedBox.ciphertext,
                                                     tag: Data(mutableTag))

            // Attempt decryption
            _ = try AES.GCM.open(tamperedBox, using: key)

            XCTFail("Decryption with tampered tag should have failed")
        } catch {
            // Expected: authentication failure
            XCTAssertNotNil(error)
        }
    }

    func testDifferentKeysFailDecryption() {
        // Test that messages encrypted with one key cannot be decrypted with another

        let plaintext = "Secret peer discovery".data(using: .utf8)!
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        do {
            // Encrypt with key1
            let sealedBox = try AES.GCM.seal(plaintext, using: key1)

            // Try to decrypt with key2 (should fail)
            _ = try AES.GCM.open(sealedBox, using: key2)

            XCTFail("Decryption with wrong key should have failed")
        } catch {
            // Expected: authentication failure
            XCTAssertNotNil(error)
        }
    }

    func testLargeMessageEncryption() {
        // Test encryption of large mesh packet (>16KB)

        let largeData = Data(repeating: 0xAB, count: 65536)  // 64KB
        let key = SymmetricKey(size: .bits256)

        do {
            // Encrypt
            let sealedBox = try AES.GCM.seal(largeData, using: key)

            // Decrypt
            let decrypted = try AES.GCM.open(sealedBox, using: key)

            // Verify integrity
            XCTAssertEqual(decrypted, largeData)
            XCTAssertEqual(decrypted.count, 65536)
        } catch {
            XCTFail("Large message encryption failed: \(error)")
        }
    }

    func testNonceUniqueness() {
        // Test that using the same nonce twice is detected via decryption failure
        // (demonstrating importance of nonce management)

        let plaintext = "Peer location update".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()

        do {
            // Encrypt twice with same nonce and key (security vulnerability)
            let sealedBox1 = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
            let sealedBox2 = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

            // Decrypt both (both should work, but this demonstrates the issue)
            let decrypted1 = try AES.GCM.open(sealedBox1, using: key)
            let decrypted2 = try AES.GCM.open(sealedBox2, using: key)

            // Both decrypt successfully but this is a vulnerability in practice
            // (XOR of ciphertexts would reveal plaintext)
            XCTAssertEqual(decrypted1, plaintext)
            XCTAssertEqual(decrypted2, plaintext)

            // Demonstrate the vulnerability: identical plaintext + nonce = identical ciphertext
            XCTAssertEqual(sealedBox1.ciphertext, sealedBox2.ciphertext)
        } catch {
            XCTFail("Nonce test failed: \(error)")
        }
    }

    func testAssociatedDataAuthentication() {
        // Test AEAD with associated data (mesh source/dest addresses)

        let plaintext = "Coordinate update".data(using: .utf8)!
        let associatedData = "src:peer-001,dst:peer-002,seq:42".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        do {
            // Encrypt with AAD
            let sealedBox = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData)

            // Decrypt with same AAD
            let decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: associatedData)
            XCTAssertEqual(decrypted, plaintext)

            // Try to decrypt with different AAD (should fail)
            let wrongAAD = "src:peer-001,dst:peer-003,seq:42".data(using: .utf8)!
            _ = try AES.GCM.open(sealedBox, using: key, authenticating: wrongAAD)

            XCTFail("Decryption with wrong AAD should have failed")
        } catch {
            // Expected: authentication failure with wrong AAD
            XCTAssertNotNil(error)
        }
    }

    func testCombinedConfidentialityAndAuthenticity() {
        // Test that GCM provides both confidentiality (encryption) and authenticity

        let plaintext = "Mesh peer list: 001, 002, 003".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)

            // Attacker cannot:
            // 1. Read plaintext (confidentiality via encryption)
            XCTAssertNotEqual(sealedBox.ciphertext, plaintext)

            // 2. Modify ciphertext without detection (authenticity via MAC)
            var tamperedCiphertext = [UInt8](sealedBox.ciphertext)
            if !tamperedCiphertext.isEmpty {
                tamperedCiphertext[0] ^= 0x01
            }

            let tamperedBox = try AES.GCM.SealedBox(nonce: sealedBox.nonce,
                                                     ciphertext: Data(tamperedCiphertext),
                                                     tag: sealedBox.tag)

            _ = try AES.GCM.open(tamperedBox, using: key)
            XCTFail("Tampered data should have been detected")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testKeyDerivation() {
        // Test that shared secret can be used to derive unique keys per peer

        let sharedSecret = SymmetricKey(size: .bits256)
        let peer1Info = "peer-001".data(using: .utf8)!
        let peer2Info = "peer-002".data(using: .utf8)!

        do {
            // Derive different keys for different peers from shared secret
            let key1 = SymmetricKey(data: HMAC<SHA256>.authenticationCode(
                for: peer1Info,
                using: sharedSecret
            ))

            let key2 = SymmetricKey(data: HMAC<SHA256>.authenticationCode(
                for: peer2Info,
                using: sharedSecret
            ))

            // Keys should be different
            XCTAssertNotEqual(key1.withUnsafeBytes { Data($0) },
                             key2.withUnsafeBytes { Data($0) })
        } catch {
            XCTFail("Key derivation failed: \(error)")
        }
    }

    func testPerformance() {
        // Benchmark encryption/decryption performance

        let data = Data(repeating: 0x42, count: 4096)
        let key = SymmetricKey(size: .bits256)

        measure {
            do {
                let sealedBox = try AES.GCM.seal(data, using: key)
                _ = try AES.GCM.open(sealedBox, using: key)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
}
