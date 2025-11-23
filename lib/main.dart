import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'app.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  debugPrint('🚀 [MAIN] Starting app initialization...');
  
  try {
    debugPrint('🚀 [MAIN] Step 1: Ensuring Flutter bindings initialized...');
  WidgetsFlutterBinding.ensureInitialized();
    debugPrint('✅ [MAIN] Step 1: Flutter bindings initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ [MAIN] Step 1 FAILED: Error initializing Flutter bindings: $e');
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  }
  
  // Load environment variables
  // Try assets first (works in all builds including release)
  // Then try root .env (works in development)
  bool envLoaded = false;
  try {
    debugPrint('🚀 [MAIN] Step 2: Loading .env file from assets...');
    // First try from assets (works in all build modes)
    await dotenv.load(fileName: 'assets/env/.env');
    envLoaded = true;
    debugPrint('✅ [MAIN] Step 2: Loaded .env file from assets');
  } catch (e) {
    debugPrint('⚠️ [MAIN] Step 2: Failed to load .env from assets: $e');
    // Fallback to root .env (for development)
    try {
      debugPrint('🚀 [MAIN] Step 2b: Trying to load .env file from root...');
      await dotenv.load(fileName: '.env');
      envLoaded = true;
      debugPrint('✅ [MAIN] Step 2b: Loaded .env file from root');
    } catch (e2) {
      debugPrint('❌ [MAIN] Step 2b: Failed to load .env from root: $e2');
      // If both fail, environment variables might not be available
    }
  }
  
  // Initialize Supabase - must succeed before app runs
  try {
    debugPrint('🚀 [MAIN] Step 3: Initializing Supabase...');
    debugPrint('🚀 [MAIN] Step 3a: Getting Supabase URL and key...');
    final url = SupabaseConfig.url;
    final anonKey = SupabaseConfig.anonKey;
    debugPrint('✅ [MAIN] Step 3a: Got Supabase URL: ${url.isNotEmpty ? 'SET (${url.length} chars)' : 'EMPTY'}');
    debugPrint('✅ [MAIN] Step 3a: Got Supabase Anon Key: ${anonKey.isNotEmpty ? 'SET (${anonKey.length} chars)' : 'EMPTY'}');
    
    if (url.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase URL or Anon Key is empty. Check your .env file.');
    }
    
    debugPrint('🚀 [MAIN] Step 3b: Calling Supabase.initialize()...');
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    debugPrint('✅ [MAIN] Step 3: Supabase initialized successfully');
  } catch (e, stackTrace) {
    // Log the error for debugging
    debugPrint('❌ [MAIN] Step 3 FAILED: Failed to initialize Supabase: $e');
    debugPrint('Stack trace: $stackTrace');
    debugPrint('Env loaded: $envLoaded');
    debugPrint('SUPABASE_URL: ${dotenv.env['SUPABASE_URL']?.isNotEmpty ?? false ? 'SET' : 'NOT SET'}');
    debugPrint('SUPABASE_ANON_KEY: ${dotenv.env['SUPABASE_ANON_KEY']?.isNotEmpty ?? false ? 'SET' : 'NOT SET'}');
    // In debug mode, rethrow to see the error immediately
    // In release mode, the app will still start but operations will fail gracefully
    assert(false, 'Supabase initialization failed: $e');
    // Don't rethrow in release builds to avoid crash loops
  }
  
  // Check location permission at startup (only check, don't request unless truly needed)
  // This allows the app to use location features when available, but doesn't prompt on every launch
  try {
    debugPrint('🚀 [MAIN] Step 4: Checking location permissions...');
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('✅ [MAIN] Step 4: Location permission status: $permission');
    // Only log the status, don't request permission here
    // Permission should be requested contextually when the user actually needs location features
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ [MAIN] Step 4: Location permission not granted, but continuing...');
      // Permission is not granted, but don't request it here
      // Let individual pages request permission when they actually need it
    }
  } catch (e, stackTrace) {
    debugPrint('⚠️ [MAIN] Step 4: Error checking location permission: $e');
    debugPrint('Stack trace: $stackTrace');
    // Silently fail - location features will request permission when needed
  }
  
  try {
    debugPrint('🚀 [MAIN] Step 5: Running BuyerApp...');
  runApp(const BuyerApp());
    debugPrint('✅ [MAIN] Step 5: BuyerApp started successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ [MAIN] Step 5 FAILED: Error running app: $e');
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  }
  
  debugPrint('✅ [MAIN] App initialization completed successfully!');
}
