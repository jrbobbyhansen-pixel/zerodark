import Foundation

// MARK: - RoleManager

class RoleManager: ObservableObject {
    @Published private(set) var roles: [String: Role] = [:]
    @Published private(set) var users: [String: User] = [:]

    func addRole(_ role: Role) {
        roles[role.name] = role
    }

    func addUser(_ user: User) {
        users[user.id] = user
    }

    func assignRole(to user: User, as role: Role) {
        users[user.id]?.roles.append(role.name)
    }

    func hasPermission(_ permission: Permission, for user: User) -> Bool {
        for roleName in user.roles {
            if let role = roles[roleName], role.permissions.contains(permission) {
                return true
            }
        }
        return false
    }
}

// MARK: - Role

struct Role {
    let name: String
    let permissions: [Permission]
}

// MARK: - User

struct User {
    let id: String
    var roles: [String] = []
}

// MARK: - Permission

enum Permission: String {
    case read
    case write
    case delete
    case admin
}

// MARK: - Role Templates

extension RoleManager {
    func createAdminRole() -> Role {
        Role(name: "Admin", permissions: [.read, .write, .delete, .admin])
    }

    func createUserRole() -> Role {
        Role(name: "User", permissions: [.read])
    }
}