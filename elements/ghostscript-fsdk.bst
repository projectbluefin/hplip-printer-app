kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/ghostscript-printer-app.git
    track: testing
    ref: d2ce02dc8965a66df2716266d14e155b1fb02b75

config:
  options:
    arch: "%{arch}"
