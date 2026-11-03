kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f32de9b075efa1de5eca6142a368012b3e1305f3

config:
  options:
    arch: '%{arch}'
