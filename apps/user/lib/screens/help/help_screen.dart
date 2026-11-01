import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// FAQ + contact.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  /// Support contacts, set at build time: --dart-define=SUPPORT_EMAIL=... --dart-define=SUPPORT_PHONE=...
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');
  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE', defaultValue: '');

  static const _faq = [
    [
      'How do I pay at a shop?',
      'Tap Scan & Pay and scan the X9 bill QR the merchant shows. Check the bill, choose your X9 wallet or prepaid card and unlock your phone to approve.'
    ],
    [
      'How do offers work?',
      'Tap "Get offer" on a banner or a shop. You get a 6-digit code valid for 30 minutes. Show it at billing and the offer is taken off your bill.'
    ],
    [
      'How do I add money to my wallet?',
      'Open Wallet → Add money, enter the amount and pay the UPI request with any UPI app. Your wallet is credited when the bank confirms.'
    ],
    [
      'What is a payment request?',
      'A shop can send you a payment link. You get a notification and can pay it from your X9 prepaid card under Payment requests.'
    ],
    [
      'A payment failed but money left my account',
      'Failed payments are reversed automatically to the wallet or card they came from. Check Transactions; if it is still missing after 24 hours, contact support with the transaction ID.'
    ],
    [
      'I lost my phone',
      'Contact support at once. We remove the lost phone so it can no longer approve payments, and you can sign in on a new phone.'
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('We are here to help', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Answers to common questions are below.', style: TextStyle(color: Colors.white70)),
            if (supportEmail.isNotEmpty || supportPhone.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(children: [
                if (supportPhone.isNotEmpty)
                  Expanded(
                    child: _ContactButton(icon: Icons.call_rounded, label: 'Call us', onTap: () => openExternal(context, 'tel:$supportPhone')),
                  ),
                if (supportPhone.isNotEmpty && supportEmail.isNotEmpty) const SizedBox(width: 10),
                if (supportEmail.isNotEmpty)
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.mail_rounded,
                      label: 'E-mail us',
                      onTap: () => openExternal(context, 'mailto:$supportEmail?subject=X9%20app%20help'),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
        const SectionTitle('Frequently asked'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final f in _faq)
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(f[0], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedAlignment: Alignment.centerLeft,
                children: [Text(f[1], style: TextStyle(color: context.x9.textSecondary, height: 1.4))],
              ),
          ]),
        ),
        const SizedBox(height: 18),
        Center(child: Text('X9 by Donezo · app v${Api.instance.appVersion}', style: TextStyle(color: context.x9.textSecondary, fontSize: 12))),
      ]),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 46,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
