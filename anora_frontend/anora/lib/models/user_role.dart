enum UserRole { patient, clinician, unset }

extension UserRoleX on UserRole {
  String get storageValue => name;

  static UserRole fromStorage(String? v) {
    return UserRole.values.firstWhere(
      (r) => r.name == v,
      orElse: () => UserRole.unset,
    );
  }
}
