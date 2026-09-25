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
    - install -d -m 0777 "%{install-root}/var/lib/hplip-printer-app" "%{install-root}/var/spool/hplip-printer-app"
