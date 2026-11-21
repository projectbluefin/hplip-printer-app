kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 6b6cd6348116830032907f68c9e0615450f9533f

  # The producer generates this gitignored include from its FSDK junction
  # before invoking bst; junction consumers must stage the same value so the
  # shared runtime layer's key (oci/printing-runtime-layer.bst) resolves here.
  - kind: local
    path: junction-files/fsdk-containers/include
    directory: include

config:
  options:
    arch: '%{arch}'
