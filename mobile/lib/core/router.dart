import 'package:go_router/go_router.dart';

import '../features/wallet/wallet_routes.dart';
import 'security/secure_storage.dart';

final _secureStore = SecureStore();

const _publicPaths = <String>{
  '/splash',
  '/onboarding',
  '/login',
  '/register',
  '/forgot',
};

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final path = state.matchedLocation;
    if (_publicPaths.contains(path)) {
      return null;
    }
    try {
      final token = await _secureStore.readToken();
      if (token == null || token.isEmpty) {
        return '/login';
      }
    } catch (_) {
      return '/login';
    }
    return null;
  },
  routes: [
    ...walletRoutes,
  ],
);