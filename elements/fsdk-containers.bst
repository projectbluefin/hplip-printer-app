kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 4bee3f7cddea6c7ef86a9bf0f3602d84d52d92ff

config:
  options:
    arch: '%{arch}'
