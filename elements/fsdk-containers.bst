kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: ce90664e5d96e27da6ae6c2aaf35a558430ea999

config:
  options:
    arch: '%{arch}'
