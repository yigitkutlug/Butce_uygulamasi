String userFacingError(Object error) {
  var message = error.toString().trim();

  const prefixes = ['Exception: ', 'ApiException: '];
  for (final prefix in prefixes) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
      break;
    }
  }

  if (message.startsWith('TimeoutException')) {
    return 'Sunucuya bağlanırken süre aşımı oldu. İnternet bağlantını kontrol edip tekrar dene.';
  }

  if (message.contains('Invalid credentials')) {
    return 'Kullanıcı adı veya parola hatalı.';
  }

  if (message.contains('Invalid token') ||
      message.contains('Oturumun süresi dolmuş')) {
    return 'Oturumun süresi dolmuş olabilir. Lütfen tekrar giriş yap.';
  }

  if (message.contains('Failed host lookup') ||
      message.contains('Connection refused')) {
    return 'Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip tekrar dene.';
  }

  return message.isEmpty ? 'Bir hata oluştu. Lütfen tekrar dene.' : message;
}

bool isAuthExpiredError(Object error) {
  final message = error.toString();
  return message.contains('Invalid token') ||
      message.contains('Oturumun süresi dolmuş');
}
