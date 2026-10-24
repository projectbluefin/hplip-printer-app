kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 961edf80eaeba39cf33f0db1a7f7b20c58ced640

config:
  options:
    arch: '%{arch}'
