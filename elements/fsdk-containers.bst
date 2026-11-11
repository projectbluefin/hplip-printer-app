kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: e9881fb392e0e82517393e6b20fa942a005f066f

config:
  options:
    arch: '%{arch}'
