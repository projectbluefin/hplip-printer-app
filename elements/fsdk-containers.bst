kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 1bd074ac7b35fa5636dc22e02658619cfac1fb9b

config:
  options:
    arch: '%{arch}'
