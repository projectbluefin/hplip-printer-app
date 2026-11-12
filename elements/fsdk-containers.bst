kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: ae374c93f7b152a25e57b95a8a607500dc26fc9a

config:
  options:
    arch: '%{arch}'
