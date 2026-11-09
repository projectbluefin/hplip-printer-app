kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f51492ab5a19f353617bc147eb2ffe705579ab58

config:
  options:
    arch: '%{arch}'
