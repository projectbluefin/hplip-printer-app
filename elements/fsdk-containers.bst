kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 970943d679b7dcbbdd2300a7fea359dd58ef72c0

config:
  options:
    arch: '%{arch}'
