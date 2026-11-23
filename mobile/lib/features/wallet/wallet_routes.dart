import 'package:go_router/go_router.dart';

import 'data/wallet_models.dart';
import 'presentation/add_card_page.dart';
import 'presentation/card_detail_page.dart';
import 'presentation/contacts_page.dart';
import 'presentation/forgot_password_page.dart';
import 'presentation/help_page.dart';
import 'presentation/history_page.dart';
import 'presentation/home_page.dart';
import 'presentation/login_page.dart';
import 'presentation/money_action_page.dart';
import 'presentation/notifications_page.dart';
import 'presentation/onboarding_page.dart';
import 'presentation/receive_page.dart';
import 'presentation/register_page.dart';
import 'presentation/security_center_page.dart';
import 'presentation/security_sub_pages.dart';
import 'presentation/splash_page.dart';
import 'presentation/transaction_detail_page.dart';
import 'presentation/transaction_success_page.dart';

/// Rutas del módulo Wallet. `core/router.dart` las agrega con `...walletRoutes`.
final List<RouteBase> walletRoutes = [
  GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
  GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
  GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
  GoRoute(path: '/register', builder: (context, state) => const RegisterPage()),
  GoRoute(path: '/forgot', builder: (context, state) => const ForgotPasswordPage()),
  GoRoute(path: '/home', builder: (context, state) => const HomePage()),
  GoRoute(path: '/cards/add', builder: (context, state) => const AddCardPage()),
  GoRoute(
    path: '/cards/detail',
    builder: (context, state) => CardDetailPage(card: state.extra! as WalletCard),
  ),
  GoRoute(
    path: '/money/:action',
    builder: (context, state) => MoneyActionPage(
      action: moneyActionFromPath(state.pathParameters['action']),
      initialContact: state.extra as WalletContact?,
    ),
  ),
  GoRoute(
    path: '/success',
    builder: (context, state) => TransactionSuccessPage(tx: state.extra! as WalletTransaction),
  ),
  GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
  GoRoute(
    path: '/transaction',
    builder: (context, state) => TransactionDetailPage(tx: state.extra! as WalletTransaction),
  ),
  GoRoute(path: '/receive', builder: (context, state) => const ReceivePage()),
  GoRoute(path: '/contacts', builder: (context, state) => const ContactsPage()),
  GoRoute(path: '/security', builder: (context, state) => const SecurityCenterPage()),
  GoRoute(path: '/security/sessions', builder: (context, state) => const SessionsPage()),
  GoRoute(path: '/security/limits', builder: (context, state) => const LimitsPage()),
  GoRoute(path: '/security/log', builder: (context, state) => const ActivityLogPage()),
  GoRoute(path: '/notifications', builder: (context, state) => const NotificationsPage()),
  GoRoute(path: '/help', builder: (context, state) => const HelpPage()),
];
