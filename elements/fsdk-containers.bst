kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: e475c60a41802d3da564bff56b9e6b3fdb083355

config:
  options:
    arch: '%{arch}'
