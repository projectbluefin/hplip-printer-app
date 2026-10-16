kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f30d3abde727b27460f52fb36088cb76aabaa8a7

config:
  options:
    arch: '%{arch}'
