# Bticino Classe 100X, local control

Answer your door from Home Assistant. This replaces the software on a Bticino Classe 100X
video intercom so the video, the two-way audio and the door release run on your own
network, and adds the Home Assistant integration that uses them.

For anyone with a Classe 100X, an MQTT broker and a Home Assistant instance.

## Requirements
| Where | Description |
|---|---|
| Intercom | Classe 100X, firmware 1.5.8 (other 1.5.x likely) |
| Home Assistant | 2024.7 or newer, with an MQTT broker |
| To flash | A Windows machine and MyHomeSuite, Bticino's own tool |
| To build | Linux, macOS or Windows, with `curl` and `git` |
| Not needed | Administrator rights, Python, Docker or WSL |

Replacing the firmware leaves the intercom unusable until the flash finishes.

## Install

Build the firmware:

```sh
curl -fsSL https://raw.githubusercontent.com/enricleon-selfhosted/bticino-c100x/main/install.sh | sh
```

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/enricleon-selfhosted/bticino-c100x/main/install.ps1 | iex"
```

It asks about your broker, your ssh key, the door commands and whether to cut Bticino's
cloud, then writes a `.fwz` file. Answers are saved in `config.yaml`, so
building again asks nothing:

```sh
./install.sh --yes        # build with the saved answers
./install.sh --docker     # build in a container instead
```

Flash the `.fwz` with MyHomeSuite. A new unit is paired with the Door Entry app afterwards,
which is what gives it a phone identity.

Then add the integration through HACS — three dots, Custom repositories, this repository,
category **Integration** — and add **Bticino Classe 100X** under Settings, Devices and
services with the intercom's address. The MQTT topic is asked for too and is
already filled in.

## Use

The integration brings 19 entities, seven services and three dashboard cards. The cards
register themselves as a dashboard resource; dashboards managed in YAML need it added
by hand:

```yaml
lovelace:
  resources:
    - url: /bticino_c100x/bticino-c100x-cards.js
      type: module
```

Put the cards wherever you like:

```yaml
type: custom:intercom-video
connect_entity: binary_sensor.intercom_connect_video
talk_entity: binary_sensor.intercom_picked_up
```

`connect_entity` is what tells the card when to open the video. Without it the card
connects whenever it is on screen, which keeps the intercom in a call.

```yaml
type: custom:intercom-button
name: Open
icon: mdi:door-open
color: green
tap_action:
  service: bticino_c100x.open_door
```

```yaml
type: custom:intercom-call-log
```

Every ring becomes an entry, like a phone's call history: the photo, answered or
missed, and whether the door was opened. Tapping an entry shows the photo full size.
`limit` (default 10) is optional; the last 50 calls are kept, the texts follow the
Home Assistant language, and a heading is yours to add like on any other card.

For a doorbell notification, trigger an automation on `binary_sensor.intercom_ringing`
and send it to your phone. The photo is taken a few seconds into the ring, so send the
message first and the photo in a second notification carrying the same `tag`, which
replaces it. The photo is at `/bticino_c100x/media/doorbell_last.jpg`, and a notification
action named `OPEN_DOOR` opens the door.

[Full walkthrough](docs/tutorial.md)

## Licence

GPL-2.0-or-later. See [LICENSE](LICENSE) for the text and [NOTICE](NOTICE) for what is
bundled and where the knowledge came from.
