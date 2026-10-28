kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 0096a3c9cb9cf6ee38825e62eff0ec529766faf1

config:
  options:
    arch: '%{arch}'
