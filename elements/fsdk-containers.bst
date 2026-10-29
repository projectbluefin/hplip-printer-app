kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: e848ccd1ea7cf4a28e993b865d68a8976a4d00ab

config:
  options:
    arch: '%{arch}'
