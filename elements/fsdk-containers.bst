kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 202bc9f6ee71bf270543605ba0df4d4d1020dd48

config:
  options:
    arch: '%{arch}'
