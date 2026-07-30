# Asterisk Config Templates (Server A)

Copy these files to your **telephony server (Server A)** and adjust values.

| Template | Install path on Server A |
|----------|--------------------------|
| `ari.conf.example` | `/etc/asterisk/ari.conf` |
| `http.conf.example` | `/etc/asterisk/http.conf` |
| `extensions.conf.example` | merge into `/etc/asterisk/extensions.conf` |
| `websocket_client.conf.example` | `/etc/asterisk/websocket_client.conf` |
| `pjsip.conf.snippet.example` | merge into `/etc/asterisk/pjsip.conf` |

## After editing

```bash
asterisk -rvvv
ari reload
dialplan reload
module reload res_websocket_client.so
```

## Verify modules

```bash
asterisk -rx "module show like chan_websocket"
asterisk -rx "module show like res_websocket_client"
asterisk -rx "module show like res_ari"
```

All should report **Running**.

## Full setup guide

See the main project [README.md](../README.md#asterisk-ari--dograh-recommended-for-sip--ui-management).
