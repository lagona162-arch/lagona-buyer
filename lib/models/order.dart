enum OrderStatus {
	draft,
	placed,
	accepted,
	prepared,
	readyForPickup,
	pickedUp,
	onTheWay,
	delivered,
	completed,
	cancelled,
}

class OrderItem {
	final String menuItemId;
	final String name;
	final int priceCents;
	final int quantity;

	const OrderItem({
		required this.menuItemId,
		required this.name,
		required this.priceCents,
		required this.quantity,
	});

	int get lineTotalCents => priceCents * quantity;
}

class Order {
	final String id;
	final String customerId;
	final String merchantId;
	final List<OrderItem> items;
	final OrderStatus status;
	final DateTime createdAt;

	const Order({
		required this.id,
		required this.customerId,
		required this.merchantId,
		required this.items,
		required this.status,
		required this.createdAt,
	});

	int get totalCents => items.fold(0, (sum, i) => sum + i.lineTotalCents);
}


