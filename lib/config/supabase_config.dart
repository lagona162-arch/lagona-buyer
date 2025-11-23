import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
	static String get url {
		final v = dotenv.env['SUPABASE_URL'];
		if (v == null || v.isEmpty) {
			throw StateError('SUPABASE_URL is not set in .env');
		}
		return v;
	}

	static String get anonKey {
		final v = dotenv.env['SUPABASE_ANON_KEY'];
		if (v == null || v.isEmpty) {
			throw StateError('SUPABASE_ANON_KEY is not set in .env');
		}
		return v;
	}
}


