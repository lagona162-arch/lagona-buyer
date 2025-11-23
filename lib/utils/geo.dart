import 'dart:math';

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
	const double r = 6371.0; // km
	final double dLat = _deg2rad(lat2 - lat1);
	final double dLon = _deg2rad(lon2 - lon1);
	final double a = sin(dLat / 2) * sin(dLat / 2) +
			cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
			sin(dLon / 2) * sin(dLon / 2);
	final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
	return r * c;
}

double _deg2rad(double deg) => deg * (pi / 180.0);


