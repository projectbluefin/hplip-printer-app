kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: c7ffadec78326d2fb984b578af24f4b3ce19552a

config:
  options:
    arch: '%{arch}'
