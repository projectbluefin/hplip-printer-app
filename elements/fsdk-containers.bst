kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 62f7349ab02ef1a51d1acb8c5fbfaffbffad1edb

config:
  options:
    arch: '%{arch}'
