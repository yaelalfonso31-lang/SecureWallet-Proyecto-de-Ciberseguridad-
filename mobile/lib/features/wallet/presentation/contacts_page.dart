import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/demo_wallet_store.dart';
import '../data/wallet_models.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Contactos (demostración local). Tocar uno abre "Enviar dinero" con ese contacto elegido.
class ContactsPage extends ConsumerWidget {
  const ContactsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(demoWalletProvider).contacts;
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Contactos')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: WalletColors.yellow,
        foregroundColor: WalletColors.ink,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo contacto', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: () async {
          final contact = await showDialog<WalletContact>(
            context: context,
            builder: (ctx) => const _NewContactDialog(),
          );
          if (contact != null) {
            ref.read(demoWalletProvider.notifier).addContact(contact);
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          for (final c in contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => context.push('/money/send', extra: c),
                  leading: InitialsAvatar(c.name, radius: 22, background: WalletColors.ice, foreground: WalletColors.navy),
                  title: Text(c.name, style: WalletText.h3),
                  subtitle: Text(c.alias, style: WalletText.muted),
                  trailing: const IconBadge(Icons.send_rounded, size: 38, color: WalletColors.navy, background: WalletColors.yellowSoft),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewContactDialog extends StatefulWidget {
  const _NewContactDialog();

  @override
  State<_NewContactDialog> createState() => _NewContactDialogState();
}

class _NewContactDialogState extends State<_NewContactDialog> {
  final _name = TextEditingController();
  final _alias = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _alias.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final alias = _alias.text.trim().isEmpty
        ? '@${name.toLowerCase().replaceAll(' ', '.')}'
        : _alias.text.trim();
    Navigator.of(context).pop(WalletContact(name: name, alias: alias));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Nuevo contacto', style: WalletText.h2),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WalletTextField(
            controller: _name,
            label: 'Nombre',
            icon: Icons.person_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          WalletTextField(controller: _alias, label: 'Alias o correo (opcional)', icon: Icons.alternate_email_rounded),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: WalletColors.blue),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
