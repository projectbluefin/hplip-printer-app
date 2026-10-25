kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 586dbbb1bd740b5e171b6d0ceb76cd7a4a73bb61

config:
  options:
    arch: '%{arch}'
