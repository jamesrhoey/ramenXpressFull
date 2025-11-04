class MenuItem {
  final String? id;
  final String name;
  final double price;
  final String image;
  final String category;
  final List<AddOn> availableAddOns;
  final List<Ingredient> ingredients;
  final int? stockQuantity;
  final String? stockStatus;

  MenuItem({
    this.id,
    required this.name,
    required this.price,
    required this.image,
    required this.category,
    this.availableAddOns = const [],
    this.ingredients = const [],
    this.stockQuantity,
    this.stockStatus,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'image': image,
      'category': category,
      'availableAddOns': availableAddOns.map((addon) => addon.toJson()).toList(),
      'ingredients': ingredients.map((ingredient) => ingredient.toJson()).toList(),
      'stockQuantity': stockQuantity,
      'stockStatus': stockStatus,
    };
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['_id']?.toString() ?? json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      price: (json['price'] ?? 0).toDouble(),
      image: json['image']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      availableAddOns: (json['availableAddOns'] as List?)
          ?.map((addon) => AddOn.fromJson(addon))
          .toList() ?? [],
      ingredients: (json['ingredients'] as List?)
          ?.map((ingredient) => Ingredient.fromJson(ingredient))
          .toList() ?? [],
      stockQuantity: json['stockQuantity']?.toInt(),
      stockStatus: json['stockStatus']?.toString(),
    );
  }

  // Helper methods for stock status
  bool get isOutOfStock => stockStatus == 'out of stock' || (stockQuantity != null && stockQuantity! <= 0);
  bool get isLowStock => stockStatus == 'low stock';
  bool get isInStock => stockStatus == 'in stock' || (!isOutOfStock && !isLowStock);
}

class AddOn {
  final String name;
  final double price;

  AddOn({
    required this.name,
    required this.price,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'price': price,
    };
  }

  factory AddOn.fromJson(Map<String, dynamic> json) {
    return AddOn(
      name: json['name']?.toString() ?? '',
      price: (json['price'] ?? 0).toDouble(),
    );
  }
}

class Ingredient {
  final String name;
  final String unit;
  final int quantity;

  Ingredient({
    required this.name,
    required this.unit,
    required this.quantity,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'unit': unit,
      'quantity': quantity,
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name']?.toString() ?? json['inventoryItem']?.toString() ?? '',
      unit: json['unit']?.toString() ?? 'pieces',
      quantity: (json['quantity'] ?? 0).toInt(),
    );
  }
} 