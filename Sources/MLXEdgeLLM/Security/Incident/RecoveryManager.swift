import Foundation
import SwiftUI

// MARK: - RecoveryManager

final class RecoveryManager: ObservableObject {
    @Published private(set) var isRestoringFromBackup = false
    @Published private(set) var isRekeyingCredentials = false
    @Published private(set) var isVerifyingIntegrity = false
    @Published private(set) var recoveryStatus: RecoveryStatus = .idle

    private let backupService: BackupService
    private let credentialService: CredentialService
    private let integrityService: IntegrityService

    init(backupService: BackupService, credentialService: CredentialService, integrityService: IntegrityService) {
        self.backupService = backupService
        self.credentialService = credentialService
        self.integrityService = integrityService
    }

    func restoreFromBackup() async {
        isRestoringFromBackup = true
        recoveryStatus = .restoringFromBackup
        do {
            try await backupService.restore()
            recoveryStatus = .backupRestored
        } catch {
            recoveryStatus = .backupRestoreFailed(error)
        }
        isRestoringFromBackup = false
    }

    func rekeyCredentials() async {
        isRekeyingCredentials = true
        recoveryStatus = .rekeyingCredentials
        do {
            try await credentialService.rekey()
            recoveryStatus = .credentialsRekeyed
        } catch {
            recoveryStatus = .credentialRekeyFailed(error)
        }
        isRekeyingCredentials = false
    }

    func verifyIntegrity() async {
        isVerifyingIntegrity = true
        recoveryStatus = .verifyingIntegrity
        do {
            try await integrityService.verify()
            recoveryStatus = .integrityVerified
        } catch {
            recoveryStatus = .integrityVerificationFailed(error)
        }
        isVerifyingIntegrity = false
    }
}

// MARK: - RecoveryStatus

enum RecoveryStatus {
    case idle
    case restoringFromBackup
    case backupRestored
    case backupRestoreFailed(Error)
    case rekeyingCredentials
    case credentialsRekeyed
    case credentialRekeyFailed(Error)
    case verifyingIntegrity
    case integrityVerified
    case integrityVerificationFailed(Error)
}

// MARK: - BackupService

protocol BackupService {
    func restore() async throws
}

// MARK: - CredentialService

protocol CredentialService {
    func rekey() async throws
}

// MARK: - IntegrityService

protocol IntegrityService {
    func verify() async throws
}