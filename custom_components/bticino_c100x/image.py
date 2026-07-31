"""The photo of the door that goes in the doorbell notification."""

from __future__ import annotations

from homeassistant.components.image import ImageEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .entity import IntercomEntity

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    add_entities([DoorbellPhoto(hass, hass.data[DOMAIN][entry.entry_id])])

class DoorbellPhoto(IntercomEntity, ImageEntity):
    """The last picture of whoever was at the door."""

    _attr_name = "Doorbell photo"
    _attr_content_type = "image/jpeg"

    def __init__(self, hass: HomeAssistant, hub) -> None:
        IntercomEntity.__init__(self, hub, "doorbell_photo")
        ImageEntity.__init__(self, hass)
        self._published: bytes | None = None

    async def async_added_to_hass(self) -> None:
        await ImageEntity.async_added_to_hass(self)
        self.async_on_remove(self.hub.add_listener(self._hub_changed))

    @callback
    def _hub_changed(self) -> None:
        if self.hub.photo is not None and self.hub.photo is not self._published:
            self._published = self.hub.photo
            self._attr_image_last_updated = dt_util.utcnow()
        self.async_write_ha_state()

    async def async_image(self) -> bytes | None:
        return self.hub.photo
