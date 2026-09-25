kind: manual
description: Build the print-only HPLIP PAPPL Printer Application.

sources:
  - kind: local
    path: Makefile
  - kind: local
    path: hplip-printer-app.c
  - kind: local
    path: hplip-plugin-verify.c
  - kind: local
    path: hplip-plugin-verify.h
  - kind: local
    path: hplip-download-policy.c
  - kind: local
    path: hplip-download-policy.h
  - kind: local
    path: hplip-printer-app.1
  - kind: local
    path: hplip-printer-app.service
  - kind: local
    path: testpage.ps
  - kind: local
    path: HP
  - kind: local
    path: scripts/hplip-plugin-state.sh
    directory: scripts
  - kind: local
    path: VERSION

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - printer-app/hplip.bst
  - fsdk-containers.bst:printing/pappl-retrofit.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/curl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/openssl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  build-commands:
    - make -j2 VERSION="$(cat VERSION)" HPLIP_OCI=1 HPLIP_PLUGIN_STATE_DIR=/var/lib/hplip-printer-app HPLIP_PLUGIN_ALT_DIR=/var/lib/hplip-printer-app LDFLAGS="$LDFLAGS -ljpeg"
    - gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=testpage.pdf testpage.ps
  install-commands:
    - make DESTDIR="%{install-root}" VERSION="$(cat VERSION)" HPLIP_OCI=1 HPLIP_PLUGIN_STATE_DIR=/var/lib/hplip-printer-app HPLIP_PLUGIN_ALT_DIR=/var/lib/hplip-printer-app LDFLAGS="$LDFLAGS -ljpeg" unitdir= install
    - install -D -m 0644 testpage.pdf "%{install-root}/usr/share/hplip-printer-app/testpage.pdf"
