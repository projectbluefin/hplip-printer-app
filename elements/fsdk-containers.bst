kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 42eb4a8e3dec51ed918f47586c82450d0ab6bc35

config:
  options:
    arch: '%{arch}'
