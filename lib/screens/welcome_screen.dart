import 'package:flutter/material.dart';

import '../config.dart';
import '../main.dart';
import '../theme.dart';

/// First launch: ask how to call the person. No account is created.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ServicesScope.of(context).prefs.setUserName(name);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: AppMark(size: 56),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appName,
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Смотрите видео вместе и переписывайтесь. '
                    'У всех в комнате оно идёт одновременно.',
                    style: text.bodyLarge?.copyWith(color: kTextDim),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'Ваше имя',
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _name.text.trim().isEmpty ? null : _submit,
                    child: const Text('Продолжить'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Почта и пароль не нужны. Имя увидят участники комнаты.',
                    style: text.bodySmall?.copyWith(color: kTextDim),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's sign: a play triangle inside a chat bubble.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kAccent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size * .32),
          topRight: Radius.circular(size * .32),
          bottomRight: Radius.circular(size * .32),
          bottomLeft: Radius.circular(size * .08),
        ),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * .68,
      ),
    );
  }
}
