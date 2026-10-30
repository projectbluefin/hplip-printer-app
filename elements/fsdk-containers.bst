kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 885f153178c61463a3d548f2d62513c7c1a3685f

config:
  options:
    arch: '%{arch}'
