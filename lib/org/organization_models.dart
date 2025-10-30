// lib/org/organization_models.dart
import 'package:shared_preferences/shared_preferences.dart';

class Organization {
  final String id;
  final String name;
  final String role;
  Organization({required this.id, required this.name, required this.role});

  factory Organization.fromMap(Map<String, dynamic> m) => Organization(
        id: m['org_id'] as String,
        name: (m['name'] ?? '') as String,
        role: (m['role'] ?? 'member') as String,
      );
}

class OrgPrefs {
  static const _kSelectedOrgId = 'selected_org_id';

  static Future<void> saveSelectedOrgId(String orgId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSelectedOrgId, orgId);
  }

  static Future<String?> loadSelectedOrgId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kSelectedOrgId);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kSelectedOrgId);
  }
}
