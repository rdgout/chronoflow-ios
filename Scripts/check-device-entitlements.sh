#!/bin/sh
set -eu
if [ -z "${CODE_SIGN_ENTITLEMENTS:-}" ]; then exit 0; fi
case "${PLATFORM_NAME:-}" in
    iphoneos) ;;
    *) echo 'Associated domains require a device-signed build.' >&2; exit 1 ;;
esac
case "${CONFIGURATION:-}" in
    DeviceSigned|Release) ;;
    *) echo 'Associated domains require DeviceSigned or Release.' >&2; exit 1 ;;
esac
if [ -z "${DEVELOPMENT_TEAM:-}" ] || [ -z "${CODE_SIGN_IDENTITY:-}" ] ||
   [ "${CODE_SIGN_IDENTITY:-}" = - ] || [ "${CODE_SIGNING_ALLOWED:-YES}" = NO ]; then
    echo 'Associated domains require an Apple team and a signing certificate.' >&2
    exit 1
fi
case "${EXPANDED_CODE_SIGN_IDENTITY:--}" in
    ''|-) echo 'Ad-hoc builds cannot carry associated domains.' >&2; exit 1 ;;
esac
