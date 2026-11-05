kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: ec93d9a3dbd196b9a4136b22ae994b08904f3c96

config:
  options:
    arch: '%{arch}'
