import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';

/// Detalle de una promoción con botón de canje protegido por biometría (B4-a).
class PromotionDetailPage extends StatefulWidget {
  const PromotionDetailPage({super.key, required this.promotionId, required this.dio});

  final int promotionId;
  final Dio dio;

  @override
  State<PromotionDetailPage> createState() => _PromotionDetailPageState();
}

class _PromotionDetailPageState extends State<PromotionDetailPage> {
  Map<String, dynamic>? _promo;
  bool _loading = true;
  bool _redeeming = false;
  bool _redeemed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPromotion();
  }

  Future<void> _loadPromotion() async {
    try {
      final res = await widget.dio.get('/promotions/${widget.promotionId}');
      setState(() {
        _promo = res.data as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _redeem() async {
    final bio = BiometricService();
    final ok = await bio.authenticate('Confirma para canjear la promoción');
    if (!ok) return;

    setState(() => _redeeming = true);
    try {
      await widget.dio.post('/promotions/${widget.promotionId}/redeem');
      setState(() {
        _redeemed = true;
        _redeeming = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Promoción canjeada!')),
        );
      }
    } on DioException catch (e) {
      setState(() => _redeeming = false);
      final status = e.response?.statusCode;
      final msg = status == 409
          ? 'Ya canjeaste esta promoción'
          : status == 400
            ? 'Promoción vencida'
            : status == 401
              ? 'Debes vincular tu cuenta bancaria para canjear'
              : errorMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      if (status == 409) setState(() => _redeemed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de promoción')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final promo = _promo!;
    final validUntil = promo['valid_until'] as String?;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            promo['title'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(promo['description'] as String),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.discount, size: 40, color: Colors.green),
                  const SizedBox(width: 16),
                  Text(
                    '${promo['discount_percent']}% de descuento',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
          if (validUntil != null) ...[
            const SizedBox(height: 8),
            Text(
              'Vigente hasta: ${_formatDate(validUntil)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Spacer(),
          if (_redeemed)
            const Chip(
              avatar: Icon(Icons.check_circle, color: Colors.green),
              label: Text('Canjeada'),
            )
          else
            FilledButton.icon(
              onPressed: _redeeming ? null : _redeem,
              icon: _redeeming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.redeem),
              label: Text(_redeeming ? 'Canjeando…' : 'Canjear promoción'),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      return '$day/$month/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
