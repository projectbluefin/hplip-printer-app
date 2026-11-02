kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 87b07743206c450a0d12df0ac84e368ec1b3e01a

config:
  options:
    arch: '%{arch}'
