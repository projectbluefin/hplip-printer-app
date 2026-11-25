kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: a95757674e9126220e68f52fbcd13ddbeb04a793

  # The producer generates this gitignored include from its FSDK junction
  # before invoking bst; junction consumers must stage the same value so the
  # shared runtime layer's key (oci/printing-runtime-layer.bst) resolves here.
  - kind: local
    path: junction-files/fsdk-containers/include
    directory: include

config:
  options:
    arch: '%{arch}'
