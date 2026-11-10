import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'wallet_models.dart';

class CardsRepository {
  CardsRepository(this._dio);

  final Dio _dio;

  Future<List<WalletCard>> list() async {
    final res = await _dio.get<dynamic>('/cards');
    return (res.data as List<dynamic>)
        .map((e) => WalletCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cards. El backend valida Luhn, cifra el número y devuelve solo last4 y token.
  Future<WalletCard> add({
    required String number,
    required String holderName,
    required int expMonth,
    required int expYear,
  }) async {
    final res = await _dio.post<dynamic>('/cards', data: {
      'number': number,
      'holder_name': holderName,
      'exp_month': expMonth,
      'exp_year': expYear,
    });
    return WalletCard.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete<dynamic>('/cards/$id');
  }
}

final cardsRepositoryProvider = Provider<CardsRepository>(
  (ref) => CardsRepository(ref.watch(walletDioProvider)),
);

final cardsProvider = FutureProvider.autoDispose<List<WalletCard>>(
  (ref) => ref.watch(cardsRepositoryProvider).list(),
);

class DefaultCardNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? cardId) {
    state = cardId;
  }
}

final defaultCardIdProvider =
    NotifierProvider<DefaultCardNotifier, String?>(DefaultCardNotifier.new);

class BlockedCardsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void setBlocked(String cardId, bool blocked) {
    final next = Set<String>.of(state);
    if (blocked) {
      next.add(cardId);
    } else {
      next.remove(cardId);
    }
    state = next;
  }
}

final blockedCardsProvider =
    NotifierProvider<BlockedCardsNotifier, Set<String>>(BlockedCardsNotifier.new);
