kind: junction

sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: 8d2701aefa44e5f030a30533f93192a6a023c811

config:
  options:
    arch: '%{arch}'
