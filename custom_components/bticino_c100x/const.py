"""Names and numbers used across the integration."""

DOMAIN = "bticino_c100x"

CONF_TOPIC = "topic"

DEFAULT_TOPIC = "bticinocontroller"

PORT_CONTROLLER = 8080
PORT_GO2RTC = 1984

STREAM_LIVE = "camera.door"
STREAM_PHOTO = "camera.door_photo"

STATUS_TIMEOUT = 210  # three missed 60s health reports

# bus states: 0 idle, 1/2 ring, 3 video, 4 connected, 6 talk
BUS_IDLE = "0"
BUS_RING_STATES = ("2", "4")  # 2 only ever follows a press
BUS_TALK = "6"  # somebody picked up, on a phone or on the wall unit

BUS_DOOR_OPENED = "*8*19*"  # prefix of a door-release frame on the riser

BUS_STAIRCASE_LIGHT = "*8*21*10##"

VIEW_OFF = "Off"
VIEW_DOOR = "Door"
VIEWS = [VIEW_OFF, VIEW_DOOR]

VOLUME_SILENT = "Silent"
VOLUMES = [VOLUME_SILENT, "Low", "Medium", "High"]
VOLUME_LEVELS = {"Low": 20, "Medium": 60, "High": 100}

PHOTO_MIN_BYTES = 2000  # smaller means no picture yet
PHOTO_MAX_BYTES = 45000  # bigger means encoder noise
PHOTO_FILENAME = "doorbell_last.jpg"

MEDIA_DIRNAME = DOMAIN
MEDIA_URL = f"/{DOMAIN}/media"
PHOTO_URL = f"{MEDIA_URL}/{PHOTO_FILENAME}"

CALLS_DIRNAME = "calls"  # per-call photos, uuid-named: the dir is public, the names are not
CALL_LOG_LIMIT = 50  # ponytail: flat cap; raise if 50 ever feels short
CALL_GRACE = 15  # seconds after a call ends still attributed to it (open, then hang up)
CALL_DEADLINE = 120  # no record stays open longer than this

EVENT_RING = f"{DOMAIN}_ring"
EVENT_CALL_LOG = f"{DOMAIN}_call_log_updated"
