#!/usr/bin/env python3
"""v6.19: prepares the iOS project that `flutter create --platforms=ios` generated for an X9 app.

  python3 patch_ios.py --dir apps/user/ios --bundle-id in.donezo.x9.user --name X9 [--min-ios 15.5]
                       [--google-plist ios/Runner/GoogleService-Info.plist] [--server-client-id ID]
                       [--team-id ABCDE12345 --profile-name "X9 User App Store" --push]

What it does (idempotent, safe to run twice):
  * Info.plist: app name, permission texts (camera, photos, location, Face ID), UPI app schemes the app may open,
    x9:// deep link, push background mode, AVPlayer over http (ad videos), export-compliance flag,
    Google sign-in client IDs (from GoogleService-Info.plist), portrait on iPhone.
  * project.pbxproj: bundle identifier, minimum iOS version, and manual signing when --team-id is given.
  * Flutter/Debug.xcconfig + Release.xcconfig: include the CocoaPods settings.
  * Runner/Runner.entitlements with aps-environment when --push is given (needs a provisioning profile with Push).
"""
import argparse
import os
import plistlib
import re
import sys

# UPI apps the app may open on iPhone (lib/services/upi_apps_ios.dart) + maps/WhatsApp used by share/directions.
QUERY_SCHEMES = ['upi', 'gpay', 'tez', 'phonepe', 'paytmmp', 'paytm', 'bhim', 'credpay', 'amazonpay', 'mobikwik',
                 'comgooglemaps', 'whatsapp']

TEXTS = {
    'NSCameraUsageDescription': 'X9 uses the camera to scan shop bill QR codes and to take KYC photos.',
    'NSPhotoLibraryUsageDescription': 'X9 lets you pick a QR code picture or a KYC document from your photos.',
    'NSPhotoLibraryAddUsageDescription': 'X9 saves your payment receipts to your photos when you ask it to.',
    'NSLocationWhenInUseUsageDescription': 'X9 uses your location to show offers and shops near you.',
    'NSFaceIDUsageDescription': 'X9 uses Face ID to unlock the app and approve your payments.',
}


def fail(msg):
    print('::error::' + msg)
    sys.exit(1)


def patch_info(path, args):
    with open(path, 'rb') as f:
        info = plistlib.load(f)
    info['CFBundleDisplayName'] = args.name
    info['CFBundleName'] = args.name
    for k, v in TEXTS.items():
        info[k] = v
    schemes = list(info.get('LSApplicationQueriesSchemes') or [])
    for s in QUERY_SCHEMES:
        if s not in schemes:
            schemes.append(s)
    info['LSApplicationQueriesSchemes'] = schemes
    modes = list(info.get('UIBackgroundModes') or [])
    if 'remote-notification' not in modes:
        modes.append('remote-notification')
    info['UIBackgroundModes'] = modes
    ats = dict(info.get('NSAppTransportSecurity') or {})
    ats['NSAllowsArbitraryLoadsForMedia'] = True  # banner / screen ad videos served over http by the X9 server
    info['NSAppTransportSecurity'] = ats
    info['ITSAppUsesNonExemptEncryption'] = False  # only standard HTTPS / HMAC: no export compliance documents
    info['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
    info['UIRequiresFullScreen'] = True

    url_types = list(info.get('CFBundleURLTypes') or [])

    def add_scheme(name, scheme):
        for t in url_types:
            if scheme in (t.get('CFBundleURLSchemes') or []):
                return
        url_types.append({'CFBundleTypeRole': 'Editor', 'CFBundleURLName': name, 'CFBundleURLSchemes': [scheme]})

    add_scheme('x9-offer-links', 'x9')  # x9://offer/CODE (same as Android)
    if args.google_plist and os.path.exists(args.google_plist):
        with open(args.google_plist, 'rb') as f:
            g = plistlib.load(f)
        if g.get('CLIENT_ID'):
            info['GIDClientID'] = g['CLIENT_ID']
        if g.get('REVERSED_CLIENT_ID'):
            add_scheme('google-sign-in', g['REVERSED_CLIENT_ID'])
        print('Google sign-in: GIDClientID and URL scheme set from GoogleService-Info.plist')
    if args.server_client_id:
        info['GIDServerClientID'] = args.server_client_id
    info['CFBundleURLTypes'] = url_types
    with open(path, 'wb') as f:
        plistlib.dump(info, f)
    print('Info.plist patched:', path)


def patch_pbxproj(path, args):
    with open(path) as f:
        s = f.read()
    # Bundle identifier: Runner -> bundle id; RunnerTests -> bundle id + .RunnerTests
    def bid(m):
        return 'PRODUCT_BUNDLE_IDENTIFIER = %s;' % (args.bundle_id + '.RunnerTests' if 'RunnerTests' in m.group(1) else args.bundle_id)
    s = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', bid, s)
    s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = %s;' % args.min_ios, s)
    s = re.sub(r'TARGETED_DEVICE_FAMILY = "[0-9,]+";', 'TARGETED_DEVICE_FAMILY = 1;', s)  # iPhone app

    if args.team_id or args.push:
        def sign_block(m):
            block = m.group(0)
            if ('PRODUCT_BUNDLE_IDENTIFIER = %s;' % args.bundle_id) not in block:
                return block  # not the Runner app target (RunnerTests, project-level settings)
            extra = []
            if args.team_id:
                block = re.sub(r'\n\s*(CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PROVISIONING_PROFILE_SPECIFIER|"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]"|CODE_SIGN_IDENTITY) = [^;]*;', '', block)
                extra += ['CODE_SIGN_STYLE = Manual;', 'DEVELOPMENT_TEAM = %s;' % args.team_id,
                          'PROVISIONING_PROFILE_SPECIFIER = "%s";' % args.profile_name,
                          '"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "%s";' % args.sign_identity]
            if args.push and 'CODE_SIGN_ENTITLEMENTS' not in block:
                extra.append('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')
            return block.replace('buildSettings = {', 'buildSettings = {\n\t\t\t\t' + '\n\t\t\t\t'.join(extra), 1)
        s = re.sub(r'isa = XCBuildConfiguration;\s*\n\s*baseConfigurationReference[^\n]*\n\s*buildSettings = \{.*?\n\t\t\t\};', sign_block, s, flags=re.S)
        s = re.sub(r'isa = XCBuildConfiguration;\s*\n\s*buildSettings = \{.*?\n\t\t\t\};', sign_block, s, flags=re.S)
    with open(path, 'w') as f:
        f.write(s)
    if ('PRODUCT_BUNDLE_IDENTIFIER = %s;' % args.bundle_id) not in s:
        fail('could not set the bundle identifier in ' + path)
    if args.team_id and ('DEVELOPMENT_TEAM = %s;' % args.team_id) not in s:
        fail('could not set manual signing in ' + path)
    print('project.pbxproj patched: bundle id %s, iOS %s%s' % (args.bundle_id, args.min_ios, ', manual signing' if args.team_id else ''))


def patch_xcconfig(flutter_dir):
    for mode in ('Debug', 'Release'):
        p = os.path.join(flutter_dir, mode + '.xcconfig')
        if not os.path.exists(p):
            continue
        line = '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.%s.xcconfig"' % mode.lower()
        with open(p) as f:
            s = f.read()
        if line not in s:
            with open(p, 'w') as f:
                f.write(line + '\n' + s)
    print('Flutter/*.xcconfig include the CocoaPods settings')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True, help='the ios/ folder of the app')
    ap.add_argument('--bundle-id', required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--min-ios', default='15.5')
    ap.add_argument('--google-plist', default='')
    ap.add_argument('--server-client-id', default='')
    ap.add_argument('--team-id', default='')
    ap.add_argument('--profile-name', default='')
    ap.add_argument('--sign-identity', default='Apple Distribution')
    ap.add_argument('--push', action='store_true')
    args = ap.parse_args()
    d = args.dir
    info = os.path.join(d, 'Runner', 'Info.plist')
    pbx = os.path.join(d, 'Runner.xcodeproj', 'project.pbxproj')
    for p in (info, pbx):
        if not os.path.exists(p):
            fail(p + ' not found: run flutter create --platforms=ios first')
    if args.team_id and not args.profile_name:
        fail('--profile-name is required with --team-id')
    patch_info(info, args)
    patch_pbxproj(pbx, args)
    patch_xcconfig(os.path.join(d, 'Flutter'))
    if args.push:
        ent = os.path.join(d, 'Runner', 'Runner.entitlements')
        with open(ent, 'wb') as f:
            plistlib.dump({'aps-environment': 'production'}, f)
        print('Runner.entitlements written (push notifications)')


if __name__ == '__main__':
    main()
