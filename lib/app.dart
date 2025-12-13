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
import 'theme/app_colors.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

class BuyerApp extends StatelessWidget {
  const BuyerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lagona Buyer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size.fromHeight(48),
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
            borderSide: const BorderSide(color: AppColors.inputBorderFocused, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
        ),
        useMaterial3: true,
      ),
      initialRoute: LoginPage.routeName,
      routes: {
        LoginPage.routeName: (context) => const LoginPage(),
        RegisterPage.routeName: (context) => const RegisterPage(),
        ServiceSelectionPage.routeName: (context) => const ServiceSelectionPage(),
        MerchantListPage.routeName: (context) => const MerchantListPage(),
        MerchantDetailPage.routeName: (context) => const MerchantDetailPage(),
        CartPage.routeName: (context) => const CartPage(),
        CheckoutPage.routeName: (context) {
          final merchantId = ModalRoute.of(context)?.settings.arguments as String?;
          if (merchantId == null) {
            return const MerchantListPage();
          }
          return CheckoutPage(merchantId: merchantId);
        },
        OrderTrackingPage.routeName: (context) {
          final orderId = ModalRoute.of(context)?.settings.arguments as String?;
          if (orderId == null) {
            return const MerchantListPage();
          }
          return OrderTrackingPage(orderId: orderId);
        },
        FindingRiderPage.routeName: (context) {
          final orderId = ModalRoute.of(context)?.settings.arguments as String?;
          if (orderId == null) {
            return const MerchantListPage();
          }
          return FindingRiderPage(orderId: orderId);
        },
        PadalaBookingPage.routeName: (context) => const PadalaBookingPage(),
        PadalaTrackingPage.routeName: (context) {
          final padalaId = ModalRoute.of(context)?.settings.arguments as String?;
          if (padalaId == null) {
            return const PadalaBookingPage();
          }
          return PadalaTrackingPage(padalaId: padalaId);
        },
        CustomerRegistrationPage.routeName: (context) => const CustomerRegistrationPage(),
        ProfilePage.routeName: (context) => const ProfilePage(),
        OrderHistoryPage.routeName: (context) {
          final initialTabIndex = ModalRoute.of(context)?.settings.arguments as int?;
          return OrderHistoryPage(initialTabIndex: initialTabIndex);
        },
      },
    );
  }
}


