kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 5bac25e2bb117f720853d57361740f0a238671e4

config:
  options:
    arch: '%{arch}'
