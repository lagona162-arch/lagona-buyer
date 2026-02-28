import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pages/merchant_list_page.dart';
import 'pages/merchant_detail_page.dart';
import 'pages/cart_page.dart';
import 'pages/order_tracking_page.dart';
import 'pages/finding_rider_page.dart';
import 'pages/padala_booking_page.dart';
import 'pages/padala_tracking_page.dart';
import 'pages/customer_registration_page.dart';
import 'pages/profile_page.dart';
import 'pages/order_history_page.dart';
import 'pages/checkout_page.dart';
import 'pages/service_selection_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

import 'theme/app_colors.dart';

/// ----------------------------
/// SnackBar Auto-Clear Observer
/// ----------------------------
class _SnackBarObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _clearSnackBars();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _clearSnackBars();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _clearSnackBars();
  }

  void _clearSnackBars() {
    try {
      final context = BuyerApp.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    } catch (e) {
      debugPrint('Error clearing snackbars: $e');
    }
  }
}

/// ----------------------------
/// Root Application
/// ----------------------------
class BuyerApp extends StatelessWidget {
  /// GLOBAL navigator key (static!)
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final NavigatorObserver _snackBarObserver = _SnackBarObserver();

  const BuyerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [_snackBarObserver],
      title: 'Lagona Buyer',
      debugShowCheckedModeBanner: false,

      /// ----------------------------
      /// Theme
      /// ----------------------------
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.error,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        dividerColor: AppColors.divider,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonPrimary,
            foregroundColor: AppColors.textWhite,
            disabledBackgroundColor: AppColors.buttonDisabled,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputBackground,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.inputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.inputBorderFocused,
              width: 2,
            ),
          ),
        ),
      ),

      /// ----------------------------
      /// Routing
      /// ----------------------------
      initialRoute: LoginPage.routeName,
      routes: {
        LoginPage.routeName: (_) => const LoginPage(),
        RegisterPage.routeName: (_) => const RegisterPage(),
        ServiceSelectionPage.routeName: (_) =>
            const ServiceSelectionPage(),
        MerchantListPage.routeName: (_) => const MerchantListPage(),
        MerchantDetailPage.routeName: (_) =>
            const MerchantDetailPage(),
        CartPage.routeName: (_) => const CartPage(),

        CheckoutPage.routeName: (context) {
          final merchantId =
              ModalRoute.of(context)?.settings.arguments as String?;
          return merchantId == null
              ? const MerchantListPage()
              : CheckoutPage(merchantId: merchantId);
        },

        OrderTrackingPage.routeName: (context) {
          final orderId =
              ModalRoute.of(context)?.settings.arguments as String?;
          return orderId == null
              ? const MerchantListPage()
              : OrderTrackingPage(orderId: orderId);
        },

        FindingRiderPage.routeName: (context) {
          final orderId =
              ModalRoute.of(context)?.settings.arguments as String?;
          return orderId == null
              ? const MerchantListPage()
              : FindingRiderPage(orderId: orderId);
        },

        PadalaBookingPage.routeName: (_) =>
            const PadalaBookingPage(),

        PadalaTrackingPage.routeName: (context) {
          final padalaId =
              ModalRoute.of(context)?.settings.arguments as String?;
          return padalaId == null
              ? const PadalaBookingPage()
              : PadalaTrackingPage(padalaId: padalaId);
        },

        CustomerRegistrationPage.routeName: (_) =>
            const CustomerRegistrationPage(),

        ProfilePage.routeName: (_) => const ProfilePage(),

        OrderHistoryPage.routeName: (context) {
          final initialTabIndex =
              ModalRoute.of(context)?.settings.arguments as int?;
          return OrderHistoryPage(
            initialTabIndex: initialTabIndex,
          );
        },
      },
    );
  }
}
