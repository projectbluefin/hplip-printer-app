kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 3d49ae5a9efb387e9c695add949ae8ec30e0b07c

config:
  options:
    arch: '%{arch}'
