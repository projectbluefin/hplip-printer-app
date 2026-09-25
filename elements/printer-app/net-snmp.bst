kind: manual
description: Build Net-SNMP for HPLIP network printer discovery.

sources:
  - kind: git_repo
    url: github:net-snmp/net-snmp.git
    track: v5.9.*
    # source-tag: v5.9.5
    ref: 95ce5af8b59ce02d458da818b4d71606d5b161f4

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/openssl.bst

config:
  configure-commands:
    - ./configure --prefix=/usr --libdir="%{libdir}" --disable-agent --disable-applications --disable-manuals --disable-embedded-perl --without-perl-modules --with-default-snmp-version=3 --with-sys-contact=none --with-sys-location=none --with-logfile=/dev/null --with-persistent-directory=/var/lib/hplip-printer-app/snmp
  build-commands:
    - make -j2
  install-commands:
    - make DESTDIR="%{install-root}" install

public:
  bst:
    split-rules:
      devel:
        (>):
          # The default rule takes only pkgconfig/*.pc, leaving the
          # directory itself in the runtime image.
          - '%{libdir}/pkgconfig'
