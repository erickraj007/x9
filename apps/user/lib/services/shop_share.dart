import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';

/// Share a shop with friends or family: name, images, location, products / services with prices and offers.
/// The phone's share sheet lists WhatsApp; pick a contact and send.
Future<void> shareShop(BuildContext context, String uuid) async {
  try {
    final r = asMap(await withProgress(context, () => Api.instance.get('/app/merchants/$uuid/share'), label: 'Preparing…'));
    final text = str(r['text']);
    final files = <XFile>[];
    try {
      final dir = await getTemporaryDirectory();
      var i = 0;
      for (final u in asList(r['images']).take(4)) {
        final res = await http.get(Uri.parse('$u')).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final f = File('${dir.path}${Platform.pathSeparator}x9_shop_${uuid.hashCode}_${i++}.jpg');
          await f.writeAsBytes(res.bodyBytes, flush: true);
          files.add(XFile(f.path, mimeType: 'image/jpeg'));
        }
      }
    } catch (_) {
      // images are a bonus: the text alone is still shared
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files, text: text, subject: str(r['shop_name']));
    } else {
      await Share.share(text, subject: str(r['shop_name']));
    }
  } catch (e) {
    if (context.mounted) showFriendlyError(context, e);
  }
}
