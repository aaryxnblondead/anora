import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_role.dart';
import '../services/storage_service.dart';

const _userRoleKey = 'user_role';

final roleProvider = StateNotifierProvider<RoleController, UserRole>(
  (ref) => RoleController(StorageService.instance),
);

class RoleController extends StateNotifier<UserRole> {
  RoleController(this._storage)
      : super(
          UserRoleX.fromStorage(
            _storage.settingsBox.get(_userRoleKey) as String?,
          ),
        );

  final StorageService _storage;

  Future<void> setRole(UserRole role) async {
    await _storage.settingsBox.put(_userRoleKey, role.storageValue);
    state = role;
  }

  Future<void> clearRole() async {
    await _storage.settingsBox.delete(_userRoleKey);
    state = UserRole.unset;
  }
}
