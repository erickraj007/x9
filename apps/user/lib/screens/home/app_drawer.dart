import 'dart:async';

import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../card/card_screen.dart';
import '../merchant/discover_screen.dart';
import '../pay/scan_pay.dart';
import '../wallet/wallet_actions.dart';
import '../help/help_screen.dart';
import '../kyc/kyc_entry.dart';
import '../history/history_screen.dart';
import '../history/statements_hub_screen.dart';
import '../notifications/notifications_screen.dart';
import '../offers/my_offers_screen.dart';
import '../offers/offers_feed_screen.dart';
import '../payment_links/payment_links_screen.dart';
import '../profile/profile_screen.dart';
import '../security/security_screen.dart';
import '../appointments/appointments_screen.dart';
import '../orders/orders_screen.dart';
import '../lifestyle/lifestyle_screen.dart';
import '../vip/vip_screen.dart';
import '../wallet/wallet_screen.dart';

/// Side bar: user header and all sections.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  /// Closes the drawer, then runs [action] with the app's root navigator context (the drawer's own context is gone by then).
  void _later(BuildContext context, FutureOr<void> Function(BuildContext) action) {
    final root = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    Future<void>.delayed(const Duration(milliseconds: 150), () => action(root));
  }

  void _open(BuildContext context, Widget page) {
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(); // close the drawer
    nav.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _signOut(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again and approve this phone with your MPIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Sign out', style: TextStyle(color: context.x9.statusText(X9Colors.error)))),
        ],
      ),
    );
    if (sure == true) await AppState.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final s = AppState.instance;
          final u = s.user;
          final name = str(u['name'], 'X9 user');
          final vip = asBool(u['is_vip']);
          return Column(children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: context.x9.surface, border: Border(bottom: BorderSide(color: context.x9.border))),
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const X9Logo.mark(height: 30),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _open(context, const ProfileScreen()),
                  child: Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: X9Colors.heroGradient),
                      child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18)),
                        Text(fmtMobile(str(u['mobile'])), style: TextStyle(color: context.x9.textSecondary)),
                        const SizedBox(height: 6),
                        vip
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(999)),
                                child: const Text('★ VIP MEMBER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10.5, letterSpacing: 0.8)),
                              )
                            : const X9ChipBadge('X9 CLUB MEMBER', fontSize: 10.5),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                _item(context, Icons.qr_code_scanner_rounded, 'Scan & Pay', () => _later(context, startScanPay)),
                _item(context, Icons.account_balance_rounded, 'Pay with UPI app', () => _later(context, startUpiAppPay)),
                _item(context, Icons.swap_horiz_rounded, 'Transfer', () => _later(context, showTransferSheet)),
                _item(context, Icons.category_rounded, 'Categories', () {
                  final nav = Navigator.of(context, rootNavigator: true);
                  Navigator.of(context).pop();
                  nav.push(MaterialPageRoute<void>(builder: (_) => CategoriesScreen(initial: asList(s.feed?['categories']))));
                }),
                const Divider(indent: 20, endIndent: 20),
                _item(context, Icons.person_rounded, 'Profile', () => _open(context, const ProfileScreen())),
                _item(context, Icons.account_balance_wallet_rounded, 'Wallet & transfers', () => _open(context, const WalletScreen()),
                    trailing: s.balancesKnown ? money(s.clubBalance) : null),
                _item(context, Icons.credit_card_rounded, 'Prepaid card', () => _open(context, const CardScreen())),
                _item(context, Icons.workspace_premium_rounded, 'X9 VIP Club', () => _open(context, const VipScreen())),
                _item(context, Icons.event_available_rounded, 'My appointments', () => _open(context, const AppointmentsScreen())),
                _item(context, Icons.shopping_bag_rounded, 'My orders', () => _open(context, const OrdersScreen())),
                _item(context, Icons.interests_rounded, 'Life style (similar offers)', () => _open(context, const LifestyleScreen())),
                _item(context, Icons.local_offer_rounded, 'Offers', () => _open(context, const OffersFeedScreen())),
                _item(context, Icons.confirmation_number_rounded, 'My offer codes', () => _open(context, const MyOffersScreen())),
                _item(context, Icons.request_page_rounded, 'Payment requests', () => _open(context, const PaymentLinksScreen()), badge: s.pendingLinks),
                _item(context, Icons.receipt_long_rounded, 'Transactions & receipts', () => _open(context, const HistoryScreen())),
                _item(context, Icons.history_rounded, 'History & export', () => _open(context, const StatementsHubScreen())),
                _item(context, Icons.notifications_rounded, 'Notifications', () => _open(context, const NotificationsScreen()), badge: s.unread),
                const Divider(indent: 20, endIndent: 20),
                _item(context, Icons.verified_user_rounded, 'KYC verification', () => _open(context, kycScreen())),
                _item(context, Icons.shield_rounded, 'Security', () => _open(context, const SecurityScreen())),
                _item(context, Icons.help_rounded, 'Help', () => _open(context, const HelpScreen())),
                _item(context, Icons.logout_rounded, 'Sign out', () => _signOut(context), color: X9Colors.error),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('X9 · Donezo', style: TextStyle(color: context.x9.textSecondary, fontSize: 12)),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, VoidCallback onTap, {int badge = 0, String? trailing, Color? color}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: color ?? X9Colors.primary),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color == null ? null : context.x9.statusText(color))),
      trailing: badge > 0
          ? Badge(label: Text('$badge'), backgroundColor: X9Colors.error)
          : trailing != null
              ? Text(trailing, style: TextStyle(fontWeight: FontWeight.w700, color: context.x9.textSecondary))
              : null,
      onTap: onTap,
    );
  }
}
