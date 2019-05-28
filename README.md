# streamplot

Experimental streaming plotter.

## Try it out

```
$ git clone git@github.com:whatupdave/streamplot.git
$ cd streamplot && zig build
$ curl -sN https://stream.wikimedia.org/v2/stream/recentchange \
  | sed -n 's/^data: \(.*\)$/\1/p' \
  | jq --unbuffered --raw-output '.type' \
  | ./zig-cache/streamplot
```
