import 'package:go_router/go_router.dart';

import '../features/wallet/presentation/home_page.dart';
import '../features/wallet/presentation/login_page.dart';
import '../features/wallet/presentation/register_page.dart';

/// TODO equipo Wallet: agregar `redirect` para mandar a /login si no hay token guardado.
final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterPage()),
    GoRoute(path: '/home', builder: (context, state) => const HomePage()),
  ],
);
