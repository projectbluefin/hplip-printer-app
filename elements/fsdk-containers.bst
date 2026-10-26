kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: a2254fdf6220e9fa24a20da68cf97e7d2af18f2a

config:
  options:
    arch: '%{arch}'
