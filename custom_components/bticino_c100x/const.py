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

EVENT_RING = f"{DOMAIN}_ring"
