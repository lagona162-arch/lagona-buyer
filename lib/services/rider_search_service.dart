import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/supabase_service.dart';

class RiderMatch {
	final String riderId;
	final LatLng riderLocation;
	final double distanceKm;
	const RiderMatch({
		required this.riderId,
		required this.riderLocation,
		required this.distanceKm,
	});
}

class RiderSearchService {
	final SupabaseService _supabaseService = SupabaseService();

	
	Future<RiderMatch?> findNearbyRider(LatLng userLocation, {double radiusKm = 5.0}) async {
		try {
			
			final riders = await _supabaseService.findNearbyRiders(
				latitude: userLocation.latitude,
				longitude: userLocation.longitude,
				radiusKm: radiusKm,
			);

			
			if (riders.isNotEmpty) {
				final closestRider = riders.first;
				return RiderMatch(
					riderId: closestRider['id'] as String,
					riderLocation: LatLng(
						closestRider['latitude'] as double,
						closestRider['longitude'] as double,
					),
					distanceKm: closestRider['distance'] as double,
				);
			}

			return null;
		} catch (e) {
			
			print('Error finding nearby rider: $e');
			return null;
		}
	}
}


