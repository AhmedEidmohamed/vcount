import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

// تجاوز التحقق من SSL على Windows (للتطوير فقط)
class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MyHttpOverrides();
  
  try {
    // ── الطريقة الأساسية: التهيئة التلقائية من google-services.json ──────
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized from google-services.json');
  } catch (e) {
    debugPrint('⚠️ Firebase auto-init failed: $e');
    debugPrint('📌 تأكد من وضع google-services.json في android/app/');
    // لا نحتاج fallback — ملف google-services.json ضروري
  }

  // ── زرع البيانات الأولية في Firestore إذا كانت قاعدة البيانات فارغة ──
  try {
    await AuthService().seedInitialData();
  } catch (e) {
    debugPrint('Seed error: $e');
  }

  runApp(const VCountApp());
}

class VCountApp extends StatelessWidget {
  const VCountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V-Count Pro',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      // دعم اتجاه النص من اليمين لليسار
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      theme: ThemeData(
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A3A6B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
