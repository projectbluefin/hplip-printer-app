kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 0b9e6bc8d56f88e1f4cac89a2ca1e2cdbe333fb8

config:
  options:
    arch: '%{arch}'
