import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapsConfig {
	static String get apiKey {
		final key = dotenv.env['MAPS_API_KEY'];
		if (key == null || key.isEmpty) {
			throw StateError('MAPS_API_KEY is not set in .env');
		}
		return key;
	}
}


