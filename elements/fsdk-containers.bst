kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 3bb94a0ee716aa57b77d78533cc51a83a31791ec

config:
  options:
    arch: '%{arch}'
