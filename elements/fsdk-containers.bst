kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: d8204407efe0f5eba877dd7a9d6daa05c4632b5d

config:
  options:
    arch: '%{arch}'
