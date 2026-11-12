kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 0bf15e3a7be37c07f99dfffb3385d7d837a07f95

config:
  options:
    arch: '%{arch}'
