enum PadalaStatus {
  pending,
  accepted,         // Rider accepted the delivery
  pickedUp,         // Rider picked up the package (with photo)
  inTransit,        // Package is on the way
  dropoff,          // Package dropped off (with photo)
  completed,        // Delivery completed
  cancelled,
}

class PadalaDelivery {
  final String id;
  final String customerId;
  final String? riderId;
  final PadalaStatus status;
  final DateTime createdAt;
  
  // Pickup details (sender)
  final String pickupAddress;
  final double pickupLatitude;
  final double pickupLongitude;
  final String senderName;
  final String senderPhone;
  final String? senderNotes;
  
  // Dropoff details (recipient)
  final String dropoffAddress;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String recipientName;
  final String recipientPhone;
  final String? recipientNotes;
  
  // Package details
  final String? packageDescription;
  final double? deliveryFee;
  
  // Delivery tracking
  final String? dropoffPhotoUrl;
  final DateTime? deliveredAt;
  
  const PadalaDelivery({
    required this.id,
    required this.customerId,
    this.riderId,
    required this.status,
    required this.createdAt,
    required this.pickupAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.senderName,
    required this.senderPhone,
    this.senderNotes,
    required this.dropoffAddress,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    required this.recipientName,
    required this.recipientPhone,
    this.recipientNotes,
    this.packageDescription,
    this.deliveryFee,
    this.dropoffPhotoUrl,
    this.deliveredAt,
  });
  
  factory PadalaDelivery.fromMap(Map<String, dynamic> map) {
    // Note: Padala details are stored in delivery_notes as JSON
    // The service layer should parse and merge them before calling this
    return PadalaDelivery(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      riderId: map['rider_id'] as String?,
      status: _statusFromString(map['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(map['created_at'] as String),
      pickupAddress: map['pickup_address'] as String? ?? 'Unknown',
      pickupLatitude: (map['pickup_latitude'] as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (map['pickup_longitude'] as num?)?.toDouble() ?? 0.0,
      senderName: map['sender_name'] as String? ?? 'Unknown',
      senderPhone: map['sender_phone'] as String? ?? '',
      senderNotes: map['sender_notes'] as String?,
      dropoffAddress: map['dropoff_address'] as String? ?? 'Unknown',
      dropoffLatitude: (map['dropoff_latitude'] as num?)?.toDouble() ?? 0.0,
      dropoffLongitude: (map['dropoff_longitude'] as num?)?.toDouble() ?? 0.0,
      recipientName: map['recipient_name'] as String? ?? 'Unknown',
      recipientPhone: map['recipient_phone'] as String? ?? '',
      recipientNotes: map['recipient_notes'] as String?,
      packageDescription: map['package_description'] as String?,
      deliveryFee: map['delivery_fee'] != null 
          ? (map['delivery_fee'] as num).toDouble() 
          : null,
      dropoffPhotoUrl: map['dropoff_photo_url'] as String?,
      deliveredAt: map['delivered_at'] != null 
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
    );
  }
  
  static PadalaStatus _statusFromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return PadalaStatus.pending;
      case 'accepted':
        return PadalaStatus.accepted;
      case 'picked_up':
      case 'pickedup':
        return PadalaStatus.pickedUp;
      case 'in_transit':
      case 'intransit':
        return PadalaStatus.inTransit;
      case 'dropoff':
      case 'drop_off':
        return PadalaStatus.dropoff;
      case 'completed':
        return PadalaStatus.completed;
      case 'cancelled':
        return PadalaStatus.cancelled;
      default:
        return PadalaStatus.pending;
    }
  }
  
  String get statusDisplay {
    switch (status) {
      case PadalaStatus.pending:
        return 'Pending';
      case PadalaStatus.accepted:
        return 'Accepted by Rider';
      case PadalaStatus.pickedUp:
        return 'Picked Up';
      case PadalaStatus.inTransit:
        return 'In Transit';
      case PadalaStatus.dropoff:
        return 'Dropped Off';
      case PadalaStatus.completed:
        return 'Completed';
      case PadalaStatus.cancelled:
        return 'Cancelled';
    }
  }
  
  bool get canTrack => status != PadalaStatus.pending && 
                       status != PadalaStatus.cancelled && 
                       riderId != null;
  
  bool get isDelivered => status == PadalaStatus.dropoff || 
                          status == PadalaStatus.completed;
}

