kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: feb393d7ee57ae86a86c863b91f5e47851be0e07

config:
  options:
    arch: '%{arch}'
