kind: manual
description: Build Debian-patched HPLIP print filters, backends, utilities and model PPDs.

sources:
  - kind: git_repo
    url: salsa:printing-team/hplip.v2.git
    track: debian/*
    # source-tag: debian/3.26.4+dfsg0-3
    ref: debian/3.26.4+dfsg0-3-0-gf27f786d5f1060cce7c92e42488bd5e5d00ba135
  - kind: patch_queue
    path: patches/oci-hplip

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-daemon-only.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/avahi-printing.bst

environment:
  PYTHON: python3
  IMAGEPROC: disable
  CUPS_DATADIR: /usr/share/cups
  PPDC_DATADIR: /usr/share/ppdc

variables:
  conf-local: >-
    --prefix=/usr
    --libdir=%{libdir}
    --disable-foomatic-rip-hplip-install
    --with-hpppddir=/usr/share/ppd/hplip/HP
    --without-drvdir
    --without-icondir
    --enable-hpcups-install
    --disable-cups-drv-install
    --enable-cups-ppd-install
    --disable-hpijs-install
    --disable-foomatic-drv-install
    --disable-foomatic-ppd-install
    --disable-imageProcessor-build
    --enable-network-build
    --disable-class-driver
    --disable-scan-build
    --disable-gui-build
    --disable-fax-build
    --disable-qt3
    --disable-qt4
    --disable-qt5
    --disable-policykit

depends:
  - printer-app/net-snmp.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/avahi-libs.bst
  - printer-app/python3-distro.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/libppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/libusb.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst

config:
  configure-commands:
    - sh debian/autogen.sh
    - ./configure %{conf-local}
  build-commands:
    - find . -name '*.ppd' -print0 | xargs -0 -r gzip -f
    - find data/ -regextype posix-extended -regex '.*\.(ldl|pcl|ps|pdf)' -print0 | xargs -0 -r gzip -f
    - USER=root HOME=/tmp python3 ./dat2drv.py
    - make -j2
  install-commands:
    - make DESTDIR="%{install-root}" install
    # libtool archives are build-time only; the Python extension ones under
    # site-packages fall outside the devel split rules.
    - find "%{install-root}" -name '*.la' -delete
    - sed -i 's|^run=.*|run=/var/lib/hplip-printer-app/run|' "%{install-root}/etc/hp/hplip.conf"
    - install -D -m 0644 debian/upstream/signing-key.asc "%{install-root}/usr/share/hplip/signing-key.asc"
    - cp prnt/ps/*.ppd.gz "%{install-root}/usr/share/ppd/hplip/HP/"
