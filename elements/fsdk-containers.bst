kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 853b05faaddb43f517fc140e16bab3de1154a979

config:
  options:
    arch: '%{arch}'
