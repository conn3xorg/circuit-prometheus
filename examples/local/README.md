# Local example

Applies circuit-prometheus to a throwaway Rocky Linux 10 container with systemd, together with node_exporter from [circuit-node-exporter](https://github.com/conn3xorg/circuit-node-exporter) for it to scrape. You need Conn3x and Podman.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To look at the result, ask Prometheus whether node_exporter is up:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  curl -s 'localhost:9090/api/v1/query?query=up'
```

Each target shows a value of `"1"`. To see a config change reload Prometheus rather than restart it, apply again with `-var scrape_interval=20s` and look at `journalctl -u prometheus`: there's a `Reloaded` line and no new `Started`.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, the key and the state.
