"""What the intercom reports about itself."""

from __future__ import annotations

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import UnitOfTemperature, UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .entity import IntercomEntity

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    hub = hass.data[DOMAIN][entry.entry_id]
    add_entities(
        [
            BusStateSensor(hub),
            LastBusMessageSensor(hub),
            UptimeSensor(hub),
            SignalSensor(hub),
            TemperatureSensor(hub),
        ]
    )

class BusStateSensor(IntercomEntity, SensorEntity):
    """What the call is doing, as the unit describes itself."""

    _attr_name = "Bus state"
    _attr_icon = "mdi:phone-in-talk"

    def __init__(self, hub) -> None:
        super().__init__(hub, "bus_state")

    @property
    def native_value(self) -> str | None:
        return self.hub.bus_state

class LastBusMessageSensor(IntercomEntity, SensorEntity):
    """Every message on the door bus, as it comes, read off the bus itself."""

    _attr_name = "Last bus message"
    _attr_icon = "mdi:phone-outgoing"

    def __init__(self, hub) -> None:
        super().__init__(hub, "last_bus_message")

    @property
    def native_value(self) -> str | None:
        return self.hub.last_bus_message

class _HealthSensor(IntercomEntity, SensorEntity):
    """Made from the health report, so it stops being believed when that stops arriving."""

    @property
    def available(self) -> bool:
        return self.hub.available

class UptimeSensor(_HealthSensor):
    """The heartbeat: how long the unit has been on."""

    _attr_name = "Uptime"
    _attr_icon = "mdi:timer-outline"
    _attr_native_unit_of_measurement = UnitOfTime.SECONDS
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, hub) -> None:
        super().__init__(hub, "uptime")

    @property
    def native_value(self) -> int | None:
        return self.hub.uptime

class SignalSensor(_HealthSensor):
    """Worth having because a weak link never announces itself as one."""

    _attr_name = "Wireless signal"
    _attr_icon = "mdi:wifi"
    _attr_native_unit_of_measurement = "dBm"
    _attr_device_class = SensorDeviceClass.SIGNAL_STRENGTH
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, hub) -> None:
        super().__init__(hub, "signal")

    @property
    def native_value(self) -> float | None:
        return self.hub.signal

class TemperatureSensor(_HealthSensor):
    _attr_name = "Temperature"
    _attr_native_unit_of_measurement = UnitOfTemperature.CELSIUS
    _attr_device_class = SensorDeviceClass.TEMPERATURE
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, hub) -> None:
        super().__init__(hub, "temperature")

    @property
    def native_value(self) -> float | None:
        return self.hub.temperature
