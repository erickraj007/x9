/// Pure parsing for the VIP Club screens (docs/SIGNUP-KYC-VIP-UPI-V6.md section 3). Amounts are paise.

int _i(dynamic v) => v is int ? v : v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? double.tryParse('${v ?? ''}')?.toInt() ?? 0;
String _s(dynamic v) => v == null ? '' : v.toString();

class VipPlan {
  const VipPlan({required this.id, required this.name, required this.price, this.description = '', this.benefits = const [], this.tier = 'VIP'});
  final int id;
  final String name;
  final int price;
  final String description;
  final List<String> benefits;

  /// COMMON | VIP (v6.11); the price is set by the Super Admin.
  final String tier;
  bool get isVipTier => tier != 'COMMON';

  factory VipPlan.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final b = m['benefits'];
    return VipPlan(
      id: _i(m['id']),
      name: _s(m['name']),
      price: _i(m['price']),
      description: _s(m['description']),
      tier: _s(m['tier']).toUpperCase() == 'COMMON' ? 'COMMON' : 'VIP',
      benefits: b is List ? b.map((e) => e is Map ? _s(e['title'] ?? e['name'] ?? e['text']) : _s(e)).where((e) => e.isNotEmpty).toList() : const [],
    );
  }
}

class VipStatus {
  const VipStatus({this.isVip = false, this.vipSince, this.kycStatus = '', this.plans = const [], this.purchase, this.referralCode = '', this.referralName = ''});
  final bool isVip;
  final String? vipSince;
  final String kycStatus;
  final List<VipPlan> plans;
  final String referralCode;
  final String referralName;

  /// Latest purchase (pending or paid), if the server sends one.
  final Map<String, dynamic>? purchase;

  bool get kycVerified => kycStatus.toUpperCase() == 'VERIFIED';

  factory VipStatus.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final p = m['plans'];
    final pur = m['purchase'];
    final ref = m['referral'] is Map ? m['referral'] as Map : const {};
    final since = _s(m['vip_since']);
    return VipStatus(
      isVip: m['is_vip'] == true || m['is_vip'] == 1 || m['is_vip'] == '1',
      vipSince: since.isEmpty ? null : since,
      kycStatus: _s(m['kyc_status']),
      plans: p is List ? p.map(VipPlan.fromJson).toList() : const [],
      purchase: pur is Map ? Map<String, dynamic>.from(pur) : null,
      referralCode: _s(ref['code']),
      referralName: _s(ref['name']),
    );
  }
}

/// PENDING | PAID | EXPIRED | FAILED | CANCELLED
String vipPurchaseStatus(Map<String, dynamic> m) => _s(m['status']).toUpperCase();

bool vipIsPaid(String status) => status == 'PAID' || status == 'SUCCESS' || status == 'COMPLETED';
bool vipIsDead(String status) => status == 'EXPIRED' || status == 'FAILED' || status == 'CANCELLED' || status == 'REJECTED';

/// Words for `fulfilment_status`.
String vipFulfilmentLabel(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'CARD_ALLOCATED':
      return 'Card ready - collect your physical card';
    case 'DISPATCHED':
      return 'Card dispatched to you';
    case 'COLLECTED':
      return 'Card collected';
    case 'CARD_PENDING':
    default:
      return 'Collect your physical card';
  }
}

/// True once [expiresAt] (ISO text) is in the past; false when missing or unreadable.
bool vipExpired(String? expiresAt, {DateTime? now}) {
  if (expiresAt == null || expiresAt.isEmpty) return false;
  final d = DateTime.tryParse(expiresAt);
  if (d == null) return false;
  return (now ?? DateTime.now()).isAfter(d);
}
