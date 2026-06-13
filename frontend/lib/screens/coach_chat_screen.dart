import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/error_messages.dart';

class CoachChatScreen extends StatefulWidget {
  const CoachChatScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends State<CoachChatScreen> {
  final _inputController = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // İlk mesaj kullanıcıya örnek soru verir; AI koçun bütçe/taksit/ürün kararı
    // odaklı olduğunu girişte anlatır.
    _messages.add(
      _ChatMessage(
        text:
            'Selam. Ben bütçe koçun. "Bunu 3500 TL\'ye alsam ne olur?" diye yazabilirsin.',
        fromUser: false,
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    _inputController.clear();

    setState(() {
      // Kullanıcının mesajı hemen listeye eklenir; backend yanıtı gelene kadar
      // gönder butonu kilitlenir.
      _sending = true;
      _messages.add(_ChatMessage(text: text, fromUser: true));
    });

    try {
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      final result =
          await widget.controller.api.coachChat(token: token, message: text);
      final reply = (result['reply'] ?? '').toString();
      setState(() {
        // Backend Gemini veya fallback mantığıyla tek bir reply alanı döndürür.
        _messages.add(_ChatMessage(text: reply, fromUser: false));
      });
    } catch (err) {
      setState(() {
        // Hata durumunda sohbet akışı bozulmasın diye kullanıcıya yeniden
        // deneyebileceği açıklayıcı bir koç mesajı eklenir.
        _messages.add(
          _ChatMessage(
            text:
                '${userFacingError(err)} Finansal koç yanıtını alamadım; bütçe, taksit veya ürün kararını biraz daha net yazarsan tekrar deneyelim.',
            fromUser: false,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t('aiCoach'))),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                // Liste ters çizilir; son mesaj altta kalır ve chat deneyimi
                // doğal görünür.
                final msg = _messages[_messages.length - 1 - index];
                final align =
                    msg.fromUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg = msg.fromUser
                    ? scheme.primaryContainer.withValues(alpha: 0.65)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.7);
                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(msg.text),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: t('coachHint'),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}
