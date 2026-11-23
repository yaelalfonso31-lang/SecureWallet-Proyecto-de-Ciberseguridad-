import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_models.dart';
import '../theme/wallet_format.dart';
import '../theme/wallet_palette.dart';

/// Logo: escudo amarillo con monedero.
class WalletLogo extends StatelessWidget {
  const WalletLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: WalletColors.goldGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: const [
          BoxShadow(color: Color(0x55FFC21A), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        color: WalletColors.navy,
        size: size * 0.55,
      ),
    );
  }
}

/// Encabezado azul con esquinas inferiores redondeadas.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 28),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        gradient: WalletColors.mainGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: child,
    );
  }
}

/// Tarjeta blanca con sombra suave.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: WalletColors.softShadow,
        border: Border.all(color: WalletColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Icono dentro de un cuadro redondeado de color.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.color = WalletColors.blue,
    this.background = WalletColors.ice,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 12, 8),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: WalletText.h3)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Botón de acceso rápido: icono grande con etiqueta.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.yellow = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool yellow;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon,
              size: 56,
              color: yellow ? WalletColors.navy : WalletColors.blue,
              background: yellow ? WalletColors.yellowSoft : WalletColors.ice,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: WalletColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BannerKind { info, warning, danger, success }

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.icon,
    this.kind = BannerKind.info,
    this.margin = EdgeInsets.zero,
  });

  final String text;
  final IconData? icon;
  final BannerKind kind;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData defaultIcon) = switch (kind) {
      BannerKind.info => (WalletColors.ice, WalletColors.blue, Icons.info_rounded),
      BannerKind.warning => (
          WalletColors.yellowSoft,
          WalletColors.yellowDark,
          Icons.warning_amber_rounded,
        ),
      BannerKind.danger => (
          const Color(0xFFFDECEC),
          WalletColors.danger,
          Icons.error_rounded,
        ),
      BannerKind.success => (
          const Color(0xFFE6F6EF),
          WalletColors.success,
          Icons.check_circle_rounded,
        ),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35, color: WalletColors.ink))),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add_card_rounded,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon, size: 88, color: WalletColors.blue, background: WalletColors.ice),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: WalletText.h2),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: WalletText.muted),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              PrimaryButton(label: actionLabel!, onPressed: onAction, icon: actionIcon),
            ],
          ],
        ),
      ),
    );
  }
}

/// Botón principal amarillo (acción más importante de la pantalla).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.blue = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool blue;

  @override
  Widget build(BuildContext context) {
    final fg = blue ? Colors.white : WalletColors.ink;
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: blue ? WalletColors.blue : WalletColors.yellow,
          foregroundColor: fg,
          disabledBackgroundColor: WalletColors.line,
          disabledForegroundColor: WalletColors.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: WalletColors.blue,
          side: const BorderSide(color: WalletColors.blue, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Campo de texto con icono, esquinas redondeadas y foco azul.
class WalletTextField extends StatelessWidget {
  const WalletTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.inputFormatters,
    this.onChanged,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final int maxLines;

  static OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      autofillHints: autofillHints,
      maxLines: obscure ? 1 : maxLines,
      enableSuggestions: !obscure,
      autocorrect: !obscure,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WalletColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: WalletColors.blue),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(WalletColors.line),
        enabledBorder: _border(WalletColors.line),
        focusedBorder: _border(WalletColors.blue, width: 2),
        errorBorder: _border(WalletColors.danger),
        focusedErrorBorder: _border(WalletColors.danger, width: 2),
      ),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(
    this.name, {
    super.key,
    this.radius = 24,
    this.background = WalletColors.yellow,
    this.foreground = WalletColors.navy,
  });

  final String name;
  final double radius;
  final Color background;
  final Color foreground;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        _initials,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: radius * 0.7),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.color = WalletColors.success,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Fila "etiqueta ........ valor" para comprobantes y detalles.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.icon, this.trailing});

  final String label;
  final String value;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: WalletColors.blue), const SizedBox(width: 10)],
          Text(label, style: WalletText.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WalletColors.ink),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

IconData txIcon(TxKind kind) {
  switch (kind) {
    case TxKind.sent:
      return Icons.north_east_rounded;
    case TxKind.received:
      return Icons.south_west_rounded;
    case TxKind.topUp:
      return Icons.add_card_rounded;
    case TxKind.withdraw:
      return Icons.account_balance_rounded;
    case TxKind.payment:
      return Icons.shopping_bag_rounded;
    case TxKind.promo:
      return Icons.local_offer_rounded;
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, this.onTap});

  final WalletTransaction tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final income = tx.isIncome;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: IconBadge(
        txIcon(tx.kind),
        color: income ? WalletColors.success : WalletColors.navy,
        background: income ? const Color(0xFFE6F6EF) : WalletColors.yellowSoft,
      ),
      title: Text(
        tx.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: WalletColors.ink),
      ),
      subtitle: Text('${tx.subtitle} · ${formatTime(tx.date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: WalletText.muted),
      trailing: Text(
        '${income ? '+' : ''}${formatMoney(tx.amountCents)}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: income ? WalletColors.success : WalletColors.ink,
        ),
      ),
    );
  }
}

void showWalletSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? WalletColors.danger : WalletColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_rounded : Icons.check_circle_rounded,
              color: error ? Colors.white : WalletColors.yellow,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: WalletText.h2),
      content: Text(message, style: WalletText.body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: danger ? WalletColors.danger : WalletColors.blue,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
