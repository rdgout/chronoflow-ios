#!/bin/sh
set -eu
if [ -z "${CODE_SIGN_ENTITLEMENTS:-}" ]; then exit 0; fi
case "${PLATFORM_NAME:-}" in
    iphoneos) ;;
    *) echo 'Associated domains require a device-signed build.' >&2; exit 1 ;;
esac
if [ "${CONFIGURATION:-}" != DeviceSigned ] || [ -z "${DEVELOPMENT_TEAM:-}" ] ||
   [ "${CODE_SIGN_IDENTITY:-}" = - ] || [ "${CODE_SIGNING_ALLOWED:-YES}" = NO ]; then
    echo 'Use DeviceSigned with an Apple development team and a signing certificate for associated domains.' >&2
    exit 1
fi
case "${EXPANDED_CODE_SIGN_IDENTITY:--}" in
    ''|-) echo 'Ad-hoc builds cannot carry associated domains.' >&2; exit 1 ;;
esac
