kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 8ed4cb90a8dbf107d013e9c57174e01a3c9dc766

config:
  options:
    arch: '%{arch}'
