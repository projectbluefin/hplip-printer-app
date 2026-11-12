kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f94d970da1a32817944de5c8c3348acd77fdcb97

config:
  options:
    arch: '%{arch}'
