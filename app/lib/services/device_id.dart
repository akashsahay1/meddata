import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Stable anonymous device identifier (no login required for free users).
class DeviceId {
  static const String _key = 'device_id';

  static Future<String> get() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    return id;
  }
}
