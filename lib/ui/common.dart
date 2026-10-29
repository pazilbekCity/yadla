import 'package:flutter/material.dart';

import '../data/database/app_database_exception.dart';
import 'app_scope.dart';
import 'strings.dart';

/// App-bar menu button allowing the user to switch the interface language
/// between Karakalpak (`kaa`), Uzbek (`uz`), and Russian (`ru`).
class LanguageSelectorButton extends StatelessWidget {
  const LanguageSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = AppScope.languageOf(context);
    return PopupMenuButton<AppLanguage>(
      key: const Key('language-selector-button'),
      tooltip: S.selectLanguage,
      icon: const Icon(Icons.language),
      onSelected: (lang) => AppScope.setLanguage(context, lang),
      itemBuilder: (_) => [
        for (final lang in AppLanguage.values)
          PopupMenuItem<AppLanguage>(
            key: Key('lang-option-${lang.code}'),
            value: lang,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  lang == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(lang.nativeName),
              ],
            ),
          ),
      ],
    );
  }
}

/// Maps a data-layer failure to a Karakalpak message. [name] is used for the
/// "deletion blocked" explanation.
String dbErrorMessage(Object error, {String? name}) {
  if (error is! AppDatabaseException) return S.errUnknown;
  switch (error.kind) {
    case DbErrorKind.notFound:
      return S.errNotFound;
    case DbErrorKind.validation:
      return S.errValidation;
    case DbErrorKind.duplicate:
      return S.errDuplicate;
    case DbErrorKind.invalidReference:
      return S.errInvalidReference;
    case DbErrorKind.hasDependents:
      return name == null ? S.errHasDependents : S.deleteBlocked(name);
    case DbErrorKind.downgrade:
      return S.errDowngrade;
    case DbErrorKind.corrupted:
      return S.errCorrupted;
    case DbErrorKind.unknown:
      return S.errUnknown;
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Asks the user to confirm a deletion. Returns true only when confirmed.
Future<bool> confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.confirmDelete(name)),
      content: Text(S.deleteIrreversible),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.delete)),
      ],
    ),
  );
  return result ?? false;
}

/// Constrains content width so lists look reasonable on tablets.
class CenteredBody extends StatelessWidget {
  const CenteredBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: child,
        ),
      );
}

/// Shows loading / error (with retry) / data states for a [Future].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.onRetry,
    required this.builder,
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(S.loadError(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: onRetry, child: Text(S.retry)),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(S.loading),
              ],
            ),
          );
        }
        return builder(context, snap.data as T);
      },
    );
  }
}

/// Dialog for creating/editing a named catalog item. [onSubmit] performs the
/// repository call; if it throws, the error is shown inline and the dialog
/// stays open so the typed text is not lost. Returns true if saved.
Future<bool> showNameDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialDescription,
  required Future<void> Function(String name, String? description) onSubmit,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      initialName: initialName,
      initialDescription: initialDescription,
      onSubmit: onSubmit,
    ),
  );
  return saved ?? false;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initialName,
    required this.initialDescription,
    required this.onSubmit,
  });

  final String title;
  final String initialName;
  final String? initialDescription;
  final Future<void> Function(String name, String? description) onSubmit;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late final _desc = TextEditingController(text: widget.initialDescription);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_name.text.trim(), _desc.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on AppDatabaseException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = dbErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('field-name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: S.name),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? S.nameRequired : null,
            ),
            TextFormField(
              key: const Key('field-description'),
              controller: _desc,
              decoration: InputDecoration(labelText: S.description),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(S.cancel)),
        FilledButton(
            key: const Key('dialog-save'),
            onPressed: _busy ? null : _submit,
            child: Text(S.save)),
      ],
    );
  }
}
