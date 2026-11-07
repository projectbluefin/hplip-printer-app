kind: manual
description: Install the HPLIP OCI supervisor and persistent state mount point.

sources:
  - kind: local
    path: files

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  install-commands:
    - install -D -m 0755 container-entrypoint.sh "%{install-root}/usr/libexec/hplip-printer-app/container-entrypoint"
    # HP's plugin signing key since HPLIP 3.25.6; Debian's
    # debian/upstream/signing-key.asc still carries only the 2009 key.
    - install -D -m 0644 hplip-plugin-signing-key-2025.asc "%{install-root}/usr/share/hplip-printer-app/hplip-plugin-signing-key-2025.asc"
    - install -d -m 0777 "%{install-root}/var/lib/hplip-printer-app" "%{install-root}/var/spool/hplip-printer-app"
