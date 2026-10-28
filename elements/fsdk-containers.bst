kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 80787ef97809740bad9e85a0b548e12293b3cd3e

config:
  options:
    arch: '%{arch}'
