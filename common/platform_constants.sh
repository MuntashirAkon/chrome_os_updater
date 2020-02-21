#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/common/platform_constants_chromeos.cc
# Fetched 1 Jan 2020

kOmahaDefaultProductionURL="https://tools.google.com/service/update2"
kOmahaDefaultAUTestURL="https://omaha-qa.sandbox.google.com/service/update2"
kOmahaUpdaterID="ChromeOSUpdateEngine"
kOmahaPlatformName="Chrome OS"
kUpdatePayloadPublicKeyPath="/usr/share/update_engine/update-payload-key.pub.pem"
kCACertificatesPath="/usr/share/chromeos-ca-certificates"
kOmahaResponseDeadlineFile="/tmp/update-check-response-deadline"
kNonVolatileDirectory="/var/lib/update_engine"
kPostinstallMountOptions=""
