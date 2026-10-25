kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 2329264f16be14327d0ebc6a89ded9561bf58013

config:
  options:
    arch: '%{arch}'
