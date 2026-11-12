kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 8313ba522445459d991c4eaa9c06a6dd50e4bf76

config:
  options:
    arch: '%{arch}'
