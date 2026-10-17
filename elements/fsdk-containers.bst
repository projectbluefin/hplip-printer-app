kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: a7919f8e5ced332395f63d6526570eedb501896c

config:
  options:
    arch: '%{arch}'
