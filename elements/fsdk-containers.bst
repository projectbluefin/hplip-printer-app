kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: abf859e87ecd227c4975e83dc73ded8564c9892a

config:
  options:
    arch: '%{arch}'
