kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 13c149384fad7b9b4ca695bcedc359b6d3979948

config:
  options:
    arch: '%{arch}'
