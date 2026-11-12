kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f8fd38a30c38b482d62861effaf041f1bff1defb

config:
  options:
    arch: '%{arch}'
