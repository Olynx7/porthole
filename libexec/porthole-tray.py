#!/usr/bin/env python3
"""Minimal StatusNotifierItem for porthole.

GNOME has no tray of its own, but the AppIndicator extension is running and
hosts anything that speaks org.kde.StatusNotifierItem. This exports one small
icon with a three-item menu so WeCom can be started without hunting through
the app grid.

Run with: porthole tray
"""
import os
import subprocess
import sys

import gi

gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"
TITLE = "企业微信"

ITEM_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <method name="ContextMenu">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="Activate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="SecondaryActivate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="Scroll">
      <arg name="delta" type="i" direction="in"/>
      <arg name="orientation" type="s" direction="in"/>
    </method>
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewAttentionIcon"/>
    <signal name="NewOverlayIcon"/>
    <signal name="NewToolTip"/>
    <signal name="NewStatus">
      <arg name="status" type="s"/>
    </signal>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get">
      <arg name="interface" type="s" direction="in"/>
      <arg name="property" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="GetAll">
      <arg name="interface" type="s" direction="in"/>
      <arg name="properties" type="a{sv}" direction="out"/>
    </method>
    <method name="Set">
      <arg name="interface" type="s" direction="in"/>
      <arg name="property" type="s" direction="in"/>
      <arg name="value" type="v" direction="in"/>
    </method>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg name="id" type="i" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg name="events" type="a(isvu)" direction="in"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <method name="AboutToShowGroup">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="updatesNeeded" type="ai" direction="out"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <signal name="LayoutUpdated">
      <arg name="revision" type="u"/>
      <arg name="parent" type="i"/>
    </signal>
    <signal name="ItemsPropertiesUpdated">
      <arg name="updatedProps" type="a(ia{sv})"/>
      <arg name="removedProps" type="a(ias)"/>
    </signal>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get">
      <arg name="interface" type="s" direction="in"/>
      <arg name="property" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="GetAll">
      <arg name="interface" type="s" direction="in"/>
      <arg name="properties" type="a{sv}" direction="out"/>
    </method>
    <method name="Set">
      <arg name="interface" type="s" direction="in"/>
      <arg name="property" type="s" direction="in"/>
      <arg name="value" type="v" direction="in"/>
    </method>
  </interface>
</node>
"""


def porthole_path():
    return os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "porthole")


def spawn(args):
    try:
        subprocess.Popen(
            [porthole_path()] + args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


_state_cache = {"value": "unknown", "at": 0.0}


def container_state():
    import time

    now = time.monotonic()
    if now - _state_cache["at"] < 5:
        return _state_cache["value"]
    _state_cache["at"] = now
    try:
        out = subprocess.run(
            ["podman", "inspect", "--format", "{{.State.Status}}", "porthole-wecom"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0:
            _state_cache["value"] = out.stdout.strip()
            return _state_cache["value"]
    except Exception:  # noqa: BLE001
        pass
    return _state_cache["value"]


class Tray:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bus_name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        self.menu_revision = 1
        self.item_info = Gio.DBusNodeInfo.new_for_xml(ITEM_XML)
        self.menu_info = Gio.DBusNodeInfo.new_for_xml(MENU_XML)

    # --- properties -----------------------------------------------------
    def item_property(self, name):
        state = container_state()
        tooltip = {
            "paused": "已暂停，点击打开",
            "running": "运行中",
            "exited": "已关机，点击打开",
        }.get(state, "点击打开")
        values = {
            "Category": GLib.Variant("s", "ApplicationStatus"),
            "Id": GLib.Variant("s", "porthole-wecom"),
            "Title": GLib.Variant("s", TITLE),
            "Status": GLib.Variant("s", "Active"),
            "WindowId": GLib.Variant("i", 0),
            "IconName": GLib.Variant("s", "wecom"),
            "IconPixmap": GLib.Variant("a(iiay)", []),
            "OverlayIconName": GLib.Variant("s", ""),
            "OverlayIconPixmap": GLib.Variant("a(iiay)", []),
            "AttentionIconName": GLib.Variant("s", ""),
            "AttentionIconPixmap": GLib.Variant("a(iiay)", []),
            "AttentionMovieName": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("wecom", [], TITLE, tooltip)),
            "ItemIsMenu": GLib.Variant("b", True),
            "Menu": GLib.Variant("o", MENU_PATH),
        }
        return values.get(name)

    def menu_property(self, name):
        values = {
            "Version": GLib.Variant("u", 3),
            "TextDirection": GLib.Variant("s", "ltr"),
            "Status": GLib.Variant("s", "normal"),
            "IconThemePath": GLib.Variant("as", []),
        }
        return values.get(name)

    # --- menu layout ----------------------------------------------------
    def menu_items(self):
        return {
            0: {"children-display": GLib.Variant("s", "submenu")},
            1: {
                "label": GLib.Variant("s", "显示企业微信"),
                "enabled": GLib.Variant("b", True),
                "visible": GLib.Variant("b", True),
            },
            2: {
                "label": GLib.Variant("s", "退出（停止容器）"),
                "enabled": GLib.Variant("b", True),
                "visible": GLib.Variant("b", True),
            },
        }

    def layout(self, parent):
        items = self.menu_items()
        children = []
        if parent == 0:
            for child_id in (1, 2):
                children.append(GLib.Variant("(ia{sv}av)", (child_id, items[child_id], [])))
        return (parent, items.get(parent, {}), children)

    # --- handlers -------------------------------------------------------
    def on_item_method(self, conn, sender, path, iface, method, params, invocation):
        # keep the icon alive even if one call is malformed
        if method in ("Activate", "SecondaryActivate"):
            spawn(["-p", "wecom", "run"])
            invocation.return_value(None)
        elif method == "ContextMenu":
            invocation.return_value(None)
        elif method == "Scroll":
            invocation.return_value(None)
        else:
            invocation.return_value(None)

    def on_properties(self, conn, sender, path, iface, method, params, invocation):
        if method == "Get":
            target, prop = params.unpack()
            getter = self.item_property if target.startswith("org.kde") else self.menu_property
            value = getter(prop)
            if value is None:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", prop)
                return
            invocation.return_value(GLib.Variant("(v)", (value,)))
        elif method == "GetAll":
            target = params.unpack()[0]
            source = self.item_property if target.startswith("org.kde") else self.menu_property
            names = (
                ["Category", "Id", "Title", "Status", "WindowId", "IconName", "IconPixmap",
                 "OverlayIconName", "OverlayIconPixmap", "AttentionIconName",
                 "AttentionIconPixmap", "AttentionMovieName", "ToolTip", "ItemIsMenu", "Menu"]
                if target.startswith("org.kde")
                else ["Version", "TextDirection", "Status", "IconThemePath"]
            )
            props = {name: source(name) for name in names}
            invocation.return_value(GLib.Variant("(a{sv})", (props,)))
        else:
            invocation.return_value(None)

    def on_menu_method(self, conn, sender, path, iface, method, params, invocation):
        if method == "GetLayout":
            parent = params.unpack()[0]
            invocation.return_value(
                GLib.Variant("(u(ia{sv}av))", (self.menu_revision, self.layout(parent)))
            )
        elif method == "GetGroupProperties":
            ids = params.unpack()[0]
            items = self.menu_items()
            result = [(i, items.get(i, {})) for i in ids]
            invocation.return_value(GLib.Variant("(a(ia{sv}))", (result,)))
        elif method == "GetProperty":
            item_id, name = params.unpack()
            items = self.menu_items()
            value = items.get(item_id, {}).get(name)
            if value is None:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", name)
            else:
                invocation.return_value(GLib.Variant("(v)", (value,)))
        elif method == "Event":
            item_id, event_id, _data, _ts = params.unpack()
            if event_id == "clicked":
                self.activate(item_id)
            invocation.return_value(None)
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "AboutToShowGroup":
            invocation.return_value(GLib.Variant("(aiai)", ([], [])))
        elif method == "EventGroup":
            for item_id, event_id, _data, _ts in params.unpack()[0]:
                if event_id == "clicked":
                    self.activate(item_id)
            invocation.return_value(GLib.Variant("(ai)", ([],)))
        else:
            invocation.return_value(None)

    def activate(self, item_id):
        if item_id == 1:
            spawn(["-p", "wecom", "run"])
        elif item_id == 2:
            # Full exit: shut the container down, then drop the icon.
            subprocess.run(
                [porthole_path(), "-p", "wecom", "down"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=180,
                start_new_session=True,
            )
            self.loop.quit()

    # --- setup ----------------------------------------------------------
    def register(self, path, xml, handler, property_handler):
        info = Gio.DBusNodeInfo.new_for_xml(xml)
        for interface in info.interfaces:
            if interface.name == "org.freedesktop.DBus.Properties":
                continue
            self.connection.register_object(
                path, interface, handler, None, None
            )
        properties = [i for i in info.interfaces if i.name == "org.freedesktop.DBus.Properties"][0]
        self.connection.register_object(path, properties, property_handler, None, None)

    def run(self):
        self.register(ITEM_PATH, ITEM_XML, self.on_item_method, self.on_properties)
        self.register(MENU_PATH, MENU_XML, self.on_menu_method, self.on_properties)

        Gio.bus_own_name_on_connection(
            self.connection, self.bus_name, Gio.BusNameOwnerFlags.NONE, None, None
        )

        try:
            self.connection.call_sync(
                "org.kde.StatusNotifierWatcher",
                "/StatusNotifierWatcher",
                "org.kde.StatusNotifierWatcher",
                "RegisterStatusNotifierItem",
                GLib.Variant("(s)", (self.bus_name,)),
                None,
                Gio.DBusCallFlags.NONE,
                4000,
                None,
            )
        except GLib.Error:
            return 1

        self.loop.run()
        return 0


def another_tray_running(connection):
    try:
        result = connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", ("org.porthole.Tray",)),
            None,
            Gio.DBusCallFlags.NONE,
            3000,
            None,
        )
        return bool(result.unpack()[0])
    except GLib.Error:
        return False


def pidfile():
    return os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
        f"porthole-{os.getuid()}",
        "tray.pid",
    )


def main():
    import atexit

    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    if another_tray_running(connection):
        return 0
    # Hold a well-known name so a second copy can detect us and exit.
    Gio.bus_own_name_on_connection(
        connection, "org.porthole.Tray", Gio.BusNameOwnerFlags.NONE, None, None
    )
    path = pidfile()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii") as handle:
        handle.write(str(os.getpid()))
    atexit.register(lambda: os.path.exists(path) and os.unlink(path))
    return Tray().run()


if __name__ == "__main__":
    sys.exit(main())
