import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../bank/data/bank_repository.dart';
import '../../wallet/data/cards_repository.dart';
import '../../wallet/data/wallet_ledger_repository.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/store_models.dart';
import '../data/store_repository.dart';
import 'store_widgets.dart';

/// Historial de pedidos del usuario.
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Mis pedidos')),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: () async {
          ref.invalidate(ordersProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [InfoBanner(kind: BannerKind.danger, text: errorMessage(e))],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Aún no tienes pedidos',
                    message: 'Cuando compres algo, tu pedido y su recibo firmado aparecerán aquí.',
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final o in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SoftCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => OrderDetailPage(order: o)),
                      ),
                      child: Row(
                        children: [
                          IconBadge(
                            orderStatusIcon(o.status),
                            color: orderStatusColor(o.status),
                            background: orderStatusColor(o.status).withValues(alpha: 0.12),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: WalletText.h3),
                                const SizedBox(height: 2),
                                Text(
                                  '${o.itemsCount} ${o.itemsCount == 1 ? 'artículo' : 'artículos'} · ${formatDate(o.createdAt.toLocal())}',
                                  style: WalletText.muted,
                                ),
                                const SizedBox(height: 6),
                                StatusChip(label: orderStatusLabel(o.status), color: orderStatusColor(o.status)),
                              ],
                            ),
                          ),
                          Text(
                            formatPrice(o.chargedCents ?? o.amountCents),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WalletColors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Detalle de un pedido: artículos, totales, recibo firmado, y acciones si está pendiente.
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.order});

  final StoreOrder order;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  final _biometric = BiometricService();
  bool? _verified;
  bool _busy = false;
  String? _error;

  void _refreshEverything() {
    ref.invalidate(ordersProvider);
    ref.invalidate(productsProvider);
    ref.invalidate(bankAccountProvider);
    ref.invalidate(bankRedemptionsProvider);
    ref.invalidate(walletBalanceProvider);
  }

  Future<void> _verify() async {
    final order = widget.order;
    if (order.receipt == null || order.signature == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(storeRepositoryProvider).verifyReceipt(order.receipt!, order.signature!);
      if (mounted) setState(() => _verified = ok);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo consultar la clave pública del Banco. ${errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: 'Cancelar pedido',
      message: '¿Seguro que quieres cancelar este pedido? No se te cobrará nada.',
      confirmLabel: 'Cancelar pedido',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(storeRepositoryProvider).cancelOrder(widget.order.orderId);
      _refreshEverything();
      if (!mounted) return;
      showWalletSnack(context, 'Pedido cancelado');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  Future<void> _payNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await _biometric.isAvailable()) {
        final ok = await _biometric.authenticate('Confirma el pago de ${formatPrice(widget.order.amountCents)}');
        if (!ok) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = 'Autenticación biométrica cancelada';
            });
          }
          return;
        }
      }
      final result = await ref.read(storeRepositoryProvider).payExistingOrder(
            widget.order,
            cardId: ref.read(defaultCardIdProvider),
          );
      _refreshEverything();
      if (!mounted) return;
      setState(() => _busy = false);
      await showReceiptSheet(context, result);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Detalle del pedido')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                IconBadge(
                  orderStatusIcon(o.status),
                  size: 60,
                  color: orderStatusColor(o.status),
                  background: orderStatusColor(o.status).withValues(alpha: 0.12),
                ),
                const SizedBox(height: 10),
                StatusChip(label: orderStatusLabel(o.status), color: orderStatusColor(o.status)),
                const SizedBox(height: 10),
                Text(
                  formatPrice(o.chargedCents ?? o.amountCents),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: WalletColors.blue),
                ),
                Text('${formatDate(o.createdAt.toLocal())} · ${formatTime(o.createdAt.toLocal())}', style: WalletText.muted),
              ],
            ),
          ),
          const SectionTitle('Artículos', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final i in o.items)
                  DetailRow('${i.quantity} × ${i.name}', formatPrice(i.unitPriceCents * i.quantity), icon: iconForName(i.name)),
                const Divider(height: 18),
                DetailRow('Subtotal', formatPrice(o.subtotalCents)),
                if (o.discountCents > 0) DetailRow('Cupón ${o.couponCode ?? ''}', '-${formatPrice(o.discountCents)}'),
                if (o.bankDiscountCents > 0) DetailRow('Promoción del Banco', '-${formatPrice(o.bankDiscountCents)}'),
                DetailRow('Total', formatPrice(o.chargedCents ?? o.amountCents)),
              ],
            ),
          ),
          if (o.isPaid && o.receipt != null) ...[
            const SectionTitle('Recibo firmado por el Banco', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReceiptView(orderId: o.orderId, receipt: o.receipt!, signature: o.signature ?? '', verified: _verified),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: _verified == null ? 'Verificar firma en mi teléfono' : 'Verificar de nuevo',
                    icon: Icons.verified_user_rounded,
                    onPressed: _busy ? null : _verify,
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            InfoBanner(kind: BannerKind.danger, text: _error!),
          ],
          if (o.isPending) ...[
            const SizedBox(height: 18),
            PrimaryButton(label: 'Pagar ahora', icon: Icons.fingerprint_rounded, loading: _busy, onPressed: _payNow),
            const SizedBox(height: 10),
            SecondaryButton(label: 'Cancelar pedido', icon: Icons.close_rounded, onPressed: _busy ? null : _cancel),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
