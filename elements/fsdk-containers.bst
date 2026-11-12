kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 08949cc7d161ad0a60cafeb2de2463995069c965

config:
  options:
    arch: '%{arch}'
