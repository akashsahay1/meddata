/// A supplier / distributor a medicine can be sourced from.
class Supplier {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Supplier copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Supplier.fromMap(Map<String, Object?> map) => Supplier(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        phone: (map['phone'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        address: (map['address'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['updated_at'] as int?) ?? 0),
      );
}
