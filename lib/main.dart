import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'app.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  try {
  WidgetsFlutterBinding.ensureInitialized();
  } catch (e, stackTrace) {
    rethrow;
  }
  
  bool envLoaded = false;
  try {
    await dotenv.load(fileName: 'assets/env/.env');
    envLoaded = true;
  } catch (e) {
    try {
      await dotenv.load(fileName: '.env');
      envLoaded = true;
    } catch (e2) {
    }
  }
  
  try {
    final url = SupabaseConfig.url;
    final anonKey = SupabaseConfig.anonKey;
    
    if (url.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase URL or Anon Key is empty. Check your .env file.');
    }
    
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  } catch (e, stackTrace) {
    assert(false, 'Supabase initialization failed: $e');
  }
  
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    }
  } catch (e, stackTrace) {
  }
  
  try {
  runApp(const BuyerApp());
  } catch (e, stackTrace) {
    rethrow;
  }
}
