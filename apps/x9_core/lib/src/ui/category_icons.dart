import 'package:flutter/material.dart';

import 'theme.dart';

/// The X9 category icon set. The central portal stores one of these keys on each category
/// (Catalogue > Categories > Icon); the apps draw the matching icon on a category-chip tile.
/// A category may instead have an uploaded image (icon_url), which wins over the key.
class CategoryIcon {
  const CategoryIcon(this.icon);
  final IconData icon;

  static const Map<String, CategoryIcon> set = {
    'restaurant': CategoryIcon(Icons.restaurant_rounded),
    'cafe': CategoryIcon(Icons.local_cafe_rounded),
    'bakery': CategoryIcon(Icons.bakery_dining_rounded),
    'grocery': CategoryIcon(Icons.local_grocery_store_rounded),
    'fashion': CategoryIcon(Icons.checkroom_rounded),
    'electronics': CategoryIcon(Icons.devices_other_rounded),
    'mobile': CategoryIcon(Icons.smartphone_rounded),
    'gym': CategoryIcon(Icons.fitness_center_rounded),
    'salon': CategoryIcon(Icons.content_cut_rounded),
    'spa': CategoryIcon(Icons.spa_rounded),
    'pharmacy': CategoryIcon(Icons.local_pharmacy_rounded),
    'hospital': CategoryIcon(Icons.local_hospital_rounded),
    'pet': CategoryIcon(Icons.pets_rounded),
    'jewellery': CategoryIcon(Icons.diamond_rounded),
    'hotel': CategoryIcon(Icons.hotel_rounded),
    'travel': CategoryIcon(Icons.flight_takeoff_rounded),
    'fuel': CategoryIcon(Icons.local_gas_station_rounded),
    'automobile': CategoryIcon(Icons.directions_car_rounded),
    'education': CategoryIcon(Icons.school_rounded),
    'books': CategoryIcon(Icons.menu_book_rounded),
    'sports': CategoryIcon(Icons.sports_cricket_rounded),
    'furniture': CategoryIcon(Icons.chair_rounded),
    'laundry': CategoryIcon(Icons.local_laundry_service_rounded),
    'entertainment': CategoryIcon(Icons.movie_rounded),
    'services': CategoryIcon(Icons.handyman_rounded),
    'veg': CategoryIcon(Icons.eco_rounded),
    'nonveg': CategoryIcon(Icons.set_meal_rounded),
    'organic': CategoryIcon(Icons.grass_rounded),
    'dental': CategoryIcon(Icons.medical_services_rounded),
    'skincare': CategoryIcon(Icons.face_retouching_natural_rounded),
    'tattoo': CategoryIcon(Icons.brush_rounded),
    'other': CategoryIcon(Icons.category_rounded),
  };

  /// Best icon key for a category with no icon chosen: matches words in its name (salon, gym, cafe, pet ...).
  static String guess(String name) {
    final n = name.toLowerCase();
    const words = <String, String>{
      'non veg': 'nonveg', 'nonveg': 'nonveg', 'veg': 'veg', 'organic': 'organic', 'salon': 'salon', 'gym': 'gym', 'cafe': 'cafe', 'coffee': 'cafe',
      'pet': 'pet', 'sport': 'sports', 'spa': 'spa', 'dental': 'dental', 'skin': 'skincare', 'tattoo': 'tattoo', 'bakery': 'bakery', 'pharmacy': 'pharmacy',
      'medical': 'pharmacy', 'hospital': 'hospital', 'clinic': 'hospital', 'mobile': 'mobile', 'electronic': 'electronics', 'fashion': 'fashion', 'cloth': 'fashion',
      'grocery': 'grocery', 'super': 'grocery', 'jewel': 'jewellery', 'hotel': 'hotel', 'travel': 'travel', 'fuel': 'fuel', 'petrol': 'fuel', 'auto': 'automobile',
      'school': 'education', 'education': 'education', 'book': 'books', 'furniture': 'furniture', 'laundry': 'laundry', 'movie': 'entertainment', 'restaurant': 'restaurant',
    };
    for (final e in words.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return 'other';
  }

  static CategoryIcon of(String? key) => set[(key ?? '').toLowerCase()] ?? set['other']!;
}

/// Category-chip tile (#FFF0F0 / #FFE2E2, X9 red #E61C24 icon; translucent red in dark mode) with the category icon (or uploaded image) and its name underneath.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.name, this.iconKey, this.iconUrl, this.onTap, this.size = 58, this.selected = false});
  final String name;
  final String? iconKey;
  final String? iconUrl;
  final VoidCallback? onTap;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ci = CategoryIcon.of(iconKey);
    final p = context.x9;
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: p.categoryBackground,
        border: Border.all(color: selected ? X9Colors.primary : p.categoryBorder, width: selected ? 2 : 1),
      ),
      child: iconUrl != null && iconUrl!.isNotEmpty
          ? Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: Image.network(iconUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(ci.icon, color: X9Colors.primary, size: size * 0.48)),
            )
          : Icon(ci.icon, color: X9Colors.primary, size: size * 0.48),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size + 18,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          tile,
          const SizedBox(height: 6),
          Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, height: 1.15, color: p.text)),
        ]),
      ),
    );
  }
}
