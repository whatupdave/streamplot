# streamplot [![Build Status](https://travis-ci.org/whatupdave/streamplot.svg?branch=master)](https://travis-ci.org/whatupdave/streamplot)

**streamplot** is a command line app that plots a histogram of streaming data.

## Example: show histogram of wikipedia updates

```
$ git clone git@github.com:whatupdave/streamplot.git
$ cd streamplot && zig build
$ curl -sN https://stream.wikimedia.org/v2/stream/recentchange \
  | sed -n 's/^data: \(.*\)$/\1/p' \
  | jq --unbuffered --raw-output '.type' \
  | ./zig-cache/streamplot
```
