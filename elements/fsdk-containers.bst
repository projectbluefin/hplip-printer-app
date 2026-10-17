kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: aaca4bb3fc30fc182e3e0da867a051af35bae045

config:
  options:
    arch: '%{arch}'
