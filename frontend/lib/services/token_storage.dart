import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _key = 'auth_token';
  // JWT normal SharedPreferences yerine secure storage içinde tutulur; böylece
  // oturum bilgisi cihazda daha güvenli saklanır.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _key, value: token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: _key);
  }

  Future<void> clear() async {
    // Logout sırasında token silinir; sonraki açılışta kullanıcı login ekranına
    // yönlendirilir.
    await _storage.delete(key: _key);
  }
}
