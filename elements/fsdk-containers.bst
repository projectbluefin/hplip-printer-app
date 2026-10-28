kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: fd66dc7b593391d33beee256b149e96c715f4b87

config:
  options:
    arch: '%{arch}'
