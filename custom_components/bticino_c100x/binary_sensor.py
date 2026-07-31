"""What the buttons and the card read."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from homeassistant.components.binary_sensor import (
    BinarySensorEntity,
    BinarySensorEntityDescription,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import IntercomHub
from .entity import IntercomEntity

@dataclass(frozen=True, kw_only=True)
class IntercomBinarySensor(BinarySensorEntityDescription):
    """One reading, and where it comes from."""

    reads: Callable[[IntercomHub], bool]

SENSORS: tuple[IntercomBinarySensor, ...] = (
    IntercomBinarySensor(
        key="call_in_progress",
        name="Call in progress",
        icon="mdi:phone-in-talk",
        reads=lambda hub: hub.call_in_progress,
    ),
    IntercomBinarySensor(
        key="ringing",
        name="Ringing",
        icon="mdi:bell-ring",
        reads=lambda hub: hub.ringing,
    ),
    IntercomBinarySensor(
        key="ready_to_answer",
        name="Ready to answer",
        icon="mdi:phone-in-talk",
        reads=lambda hub: hub.ready_to_answer,
    ),
    IntercomBinarySensor(
        key="green_colour",
        name="Green colour",
        icon="mdi:phone-in-talk",
        reads=lambda hub: hub.green_colour,
    ),
    IntercomBinarySensor(
        key="connect_video",
        name="Connect video",
        icon="mdi:video-wireless",
        reads=lambda hub: hub.connect_video,
    ),
    IntercomBinarySensor(
        key="idle",
        name="Idle",
        icon="mdi:video-off",
        reads=lambda hub: hub.idle,
    ),
    IntercomBinarySensor(
        key="show_door_camera",
        name="Show door camera",
        icon="mdi:video",
        reads=lambda hub: hub.show_door_camera,
    ),
    IntercomBinarySensor(
        key="picked_up",
        name="Picked up",
        icon="mdi:microphone",
        reads=lambda hub: hub.picked_up,
    ),
    IntercomBinarySensor(
        key="connecting",
        name="Connecting",
        icon="mdi:phone-ring",
        reads=lambda hub: hub.connecting,
    ),
)

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    hub = hass.data[DOMAIN][entry.entry_id]
    add_entities(IntercomBinarySensorEntity(hub, description) for description in SENSORS)

class IntercomBinarySensorEntity(IntercomEntity, BinarySensorEntity):
    entity_description: IntercomBinarySensor

    def __init__(self, hub: IntercomHub, description: IntercomBinarySensor) -> None:
        super().__init__(hub, description.key)
        self.entity_description = description

    @property
    def is_on(self) -> bool:
        return self.entity_description.reads(self.hub)
