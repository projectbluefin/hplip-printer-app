kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: e16c4ee3886a64e817e1bfe695c7e826ff4502b2

config:
  options:
    arch: '%{arch}'
