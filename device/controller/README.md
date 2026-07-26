# The controller

`bundle.js` is the program that runs on the intercom: it reads the door bus, answers the
HTTP API and publishes to MQTT. It is built from
[slyoldfox/c300x-controller](https://github.com/slyoldfox/c300x-controller) at tag
`v2024.9.1` with the patches in `../patches/`, and committed here so installing needs no
build tools.

To rebuild it:

```sh
../build-controller.sh          # needs node 18, or --docker
md5sum ../build/source/dist/bundle-webrtc.js
```

The result matches `bundle.js.md5`.
