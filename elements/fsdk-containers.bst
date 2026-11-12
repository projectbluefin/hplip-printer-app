kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: daf7b6e89234df5317b7cd56359d9722d710d253

config:
  options:
    arch: '%{arch}'
