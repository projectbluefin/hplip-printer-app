kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 4fd86015dd7908d4968ff438e9c35df040db31eb

  # The producer generates this gitignored include from its FSDK junction
  # before invoking bst; junction consumers must stage the same value so the
  # shared runtime layer's key (oci/printing-runtime-layer.bst) resolves here.
  - kind: local
    path: junction-files/fsdk-containers/include
    directory: include

config:
  options:
    arch: '%{arch}'
