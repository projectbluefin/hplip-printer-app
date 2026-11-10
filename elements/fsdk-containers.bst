kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 95647c3e1514aa22a28af8bff323c0f6fac7c2ed

config:
  options:
    arch: '%{arch}'
