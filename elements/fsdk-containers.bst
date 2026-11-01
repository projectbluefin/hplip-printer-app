kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 64b46198c5e26db92e3a131f673076db40d9e181

config:
  options:
    arch: '%{arch}'
