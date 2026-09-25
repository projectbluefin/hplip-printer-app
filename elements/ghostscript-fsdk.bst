kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/ghostscript-printer-app.git
    track: testing
    ref: daf785716b1531e89236e6c8a4c6f82737d11e40

config:
  options:
    arch: "%{arch}"
