kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 293b383bcfaec6edce48597cabf50472dfac4563

config:
  options:
    arch: '%{arch}'
