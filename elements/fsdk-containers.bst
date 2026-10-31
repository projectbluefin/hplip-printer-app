kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 5dcdaad042487681ab18c5437d8c1fad73a962c5

config:
  options:
    arch: '%{arch}'
