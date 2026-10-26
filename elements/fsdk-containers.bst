kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 8377ed98948a3457eec8fd1e127e4ea442cd7d42

config:
  options:
    arch: '%{arch}'
