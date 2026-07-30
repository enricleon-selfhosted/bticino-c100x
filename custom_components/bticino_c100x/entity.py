"""What every entity here has in common."""

from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity

from .const import DOMAIN, PORT_GO2RTC
from .coordinator import IntercomHub

class IntercomEntity(Entity):
    """An entity that follows the hub and holds no logic of its own."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, hub: IntercomHub, key: str) -> None:
        self.hub = hub
        self._attr_unique_id = f"{hub.host}_{key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, hub.host)},
            name="Intercom",
            manufacturer="Bticino",
            model="Classe 100X",
            configuration_url=f"http://{hub.host}:{PORT_GO2RTC}",
        )

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(self.hub.add_listener(self.async_write_ha_state))
