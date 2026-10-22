kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: a91e3383fbdf8bbdb31578218e5ae9204e81938d

config:
  options:
    arch: '%{arch}'
