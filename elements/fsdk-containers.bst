kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 21bb9be1940c9c3401acdfe5a1235dbb29833783

  # The producer generates this gitignored include from its FSDK junction
  # before invoking bst; junction consumers must stage the same value so the
  # shared runtime layer's key (oci/printing-runtime-layer.bst) resolves here.
  - kind: local
    path: junction-files/fsdk-containers/include
    directory: include

config:
  options:
    arch: '%{arch}'
