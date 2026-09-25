kind: stack
description: HPLIP print appliance with one canonical FSDK CUPS provider.

depends:
  - printer-app/application.bst
  - printer-app/hplip.bst
  - printer-app/net-snmp.bst
  - printer-app/python3-distro.bst
  - printer-app/runtime-files.bst
  - fsdk-containers.bst:printing/base.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ca-certificates.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/catatonit.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/dbus.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/gnupg.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/gzip.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/grep.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3-dbus.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3-pil.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/pygobject.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/which.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/xz.bst
