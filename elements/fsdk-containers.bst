kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 491fedf1d8504597204ece19b0f7866f3cec8f9e

config:
  options:
    arch: '%{arch}'
