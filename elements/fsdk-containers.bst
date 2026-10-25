kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 213e572f0c1e011d060aa984392b53deca3d7048

config:
  options:
    arch: '%{arch}'
