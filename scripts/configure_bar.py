#!/usr/bin/env python3
"""Safely place Music Toolbar and restore Omarchy Media in the host bar config.

Reads are bounded and reject symlinks with O_NOFOLLOW. Writes use a private
same-directory temporary file and atomic rename while preserving the original
configuration mode. The state file records the user's original media placements
and disabledPlugins state so uninstall can restore them.
"""

import argparse
import json
import os
import stat
import tempfile

MAX_BYTES = 2 * 1024 * 1024
SECTIONS = ("left", "center", "right")


def open_regular_no_follow(path):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    fd = os.open(path, flags)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(f"refusing to read a non-regular file: {path}")
        if info.st_size > MAX_BYTES:
            raise OSError(f"refusing to read an oversized file: {path}")
        return fd, stat.S_IMODE(info.st_mode)
    except BaseException:
        os.close(fd)
        raise


def read_json_no_follow(path):
    fd, mode = open_regular_no_follow(path)
    try:
        limit = MAX_BYTES + 1
        chunks = []
        total = 0
        while total < limit:
            chunk = os.read(fd, min(65536, limit - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
        if total > MAX_BYTES:
            raise OSError(f"refusing to read an oversized file: {path}")
    finally:
        os.close(fd)
    return json.loads(b"".join(chunks).decode("utf-8")), mode


def atomic_write_json(path, value, mode=None):
    directory = os.path.dirname(path) or "."
    temp_fd, temp_path = tempfile.mkstemp(prefix=".music-toolbar-shell.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            if mode is not None:
                os.fchmod(handle.fileno(), mode)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
        directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass
        raise


def default_config():
    # Conservative fallback based on the official Quattro bar configuration.
    return {
        "version": 1,
        "idle": {"screensaver": 150, "lock": 300},
        "bar": {
            "position": "top",
            "background": "opaque",
            "centerAnchor": "omarchy.clock",
            "layout": {
                "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}],
                "center": [
                    {"id": "omarchy.indicators"},
                    {
                        "id": "omarchy.clock",
                        "format": "dddd HH:mm",
                        "formatAlt": "d MMMM 'W'ww yyyy",
                        "verticalFormat": "HH\n—\nmm",
                    },
                    {"id": "omarchy.elsewhen"},
                    {"id": "omarchy.weather"},
                    {"id": "omarchy.system-update"},
                ],
                "right": [
                    {"id": "omarchy.keyboard-layout"},
                    {"id": "omarchy.tray"},
                    {"id": "omarchy.agents"},
                    {"id": "omarchy.bluetooth"},
                    {"id": "omarchy.network"},
                    {"id": "omarchy.audio"},
                    {"id": "omarchy.monitor"},
                    {"id": "omarchy.power"},
                ],
            },
        },
        "plugins": [],
    }


def load_config(path, template_path=None):
    try:
        config, mode = read_json_no_follow(path)
        if not isinstance(config, dict):
            raise ValueError("bar configuration must contain a JSON object")
        return config, mode
    except FileNotFoundError:
        if template_path:
            try:
                config, _ = read_json_no_follow(template_path)
                if isinstance(config, dict):
                    return config, None
            except (OSError, ValueError, json.JSONDecodeError):
                pass
        return default_config(), None


def read_state(path):
    try:
        state, _ = read_json_no_follow(path)
        return state if isinstance(state, dict) else None
    except FileNotFoundError:
        return None


def write_state(path, value):
    directory = os.path.dirname(path)
    if not os.path.isdir(directory):
        raise OSError(f"plugin directory does not exist: {directory}")
    atomic_write_json(path, value, 0o600)


def layout_for(config):
    bar = config.setdefault("bar", {})
    if not isinstance(bar, dict):
        raise ValueError("bar configuration entry must be an object")
    layout = bar.setdefault("layout", {})
    if not isinstance(layout, dict):
        raise ValueError("bar layout must be an object")
    return layout


def entry_id(entry):
    return entry.get("id") if isinstance(entry, dict) else None


def collect_entries(layout, target_id):
    saved = []
    for section, entries in layout.items():
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if entry_id(entry) == target_id:
                saved.append({"section": section, "index": index, "entry": entry})
    return saved


def remove_id(layout, target_id):
    for section, entries in list(layout.items()):
        if isinstance(entries, list):
            layout[section] = [entry for entry in entries if entry_id(entry) != target_id]


def has_id(layout, target_id):
    return any(entry_id(entry) == target_id for entries in layout.values() if isinstance(entries, list) for entry in entries)


def disabled_plugins(config):
    value = config.get("disabledPlugins", [])
    if not isinstance(value, list):
        raise ValueError("disabledPlugins must be an array in the bar configuration")
    return value


def set_plugin_disabled(config, plugin_id, should_disable, key_was_present):
    values = list(disabled_plugins(config))
    if should_disable:
        if plugin_id not in values:
            values.append(plugin_id)
    else:
        values = [value for value in values if value != plugin_id]

    if values or key_was_present:
        config["disabledPlugins"] = values
    else:
        config.pop("disabledPlugins", None)


def place_widget(layout, plugin_id, section):
    if section not in SECTIONS:
        raise ValueError(f"invalid bar section: {section}")
    entries = layout.setdefault(section, [])
    if not isinstance(entries, list):
        raise ValueError(f"bar layout {section} entry must be an array")

    anchor_id = {"left": "omarchy.menu", "center": "omarchy.clock"}.get(section)
    anchor_index = next((i for i, entry in enumerate(entries) if entry_id(entry) == anchor_id), None) if anchor_id else None
    insert_at = anchor_index + 1 if anchor_index is not None else len(entries)
    entries.insert(insert_at, {"id": plugin_id})


def enable(config, plugin_id, stock_id, state_path, section):
    layout = layout_for(config)
    disabled = disabled_plugins(config)
    state = read_state(state_path)
    if state is None:
        state = {
            "schemaVersion": 1,
            "pluginId": plugin_id,
            "stockId": stock_id,
            "stockEntries": collect_entries(layout, stock_id),
            "stockWasDisabled": stock_id in disabled,
            "disabledPluginsWasPresent": "disabledPlugins" in config,
        }
        write_state(state_path, state)
    else:
        # Older Music Toolbar state files saved placements but predate the
        # disabledPlugins snapshot. Migrate those fields before changing the bar config.
        changed = False
        if "stockWasDisabled" not in state:
            state["stockWasDisabled"] = stock_id in disabled
            changed = True
        if "disabledPluginsWasPresent" not in state:
            state["disabledPluginsWasPresent"] = "disabledPlugins" in config
            changed = True
        if changed:
            write_state(state_path, state)

    remove_id(layout, plugin_id)
    remove_id(layout, stock_id)
    place_widget(layout, plugin_id, section)
    set_plugin_disabled(config, stock_id, True, True)


def _saved_index(item):
    try:
        return max(0, int(item.get("index", 0)))
    except (TypeError, ValueError):
        return 0


def restore_stock_entries(layout, state, stock_id):
    if has_id(layout, stock_id):
        return
    saved = state.get("stockEntries", [])
    if not isinstance(saved, list):
        return
    safe_items = [item for item in saved if isinstance(item, dict) and isinstance(item.get("entry"), dict)]
    for item in sorted(safe_items, key=lambda value: (str(value.get("section", "center")), _saved_index(value))):
        section = str(item.get("section", "center"))
        entries = layout.setdefault(section, [])
        if not isinstance(entries, list):
            entries = []
            layout[section] = entries
        entries.insert(min(_saved_index(item), len(entries)), item["entry"])


def disable(config, plugin_id, stock_id, state_path):
    layout = layout_for(config)
    remove_id(layout, plugin_id)
    state = read_state(state_path)
    if state is None:
        # Without an install record, preserve the current disabledPlugins state
        # and use the stock plugin's usual right-section position as a fallback.
        current_disabled = stock_id in disabled_plugins(config)
        set_plugin_disabled(config, stock_id, current_disabled, "disabledPlugins" in config)
        if not has_id(layout, stock_id):
            right = layout.setdefault("right", [])
            if not isinstance(right, list):
                raise ValueError("bar layout right entry must be an array")
            right.append({"id": stock_id})
        return

    restore_stock_entries(layout, state, stock_id)
    current_disabled = stock_id in disabled_plugins(config)
    stock_was_disabled = state.get("stockWasDisabled", current_disabled) is True
    disabled_key_was_present = state.get("disabledPluginsWasPresent", "disabledPlugins" in config) is True
    set_plugin_disabled(config, stock_id, stock_was_disabled, disabled_key_was_present)


def main():
    parser = argparse.ArgumentParser(description="Edit the Omarchy shell bar layout safely.")
    parser.add_argument("--action", choices=("enable", "disable"), required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--template", help="optional stock bar configuration used when the target is missing")
    parser.add_argument("--state", required=True)
    parser.add_argument("--plugin-id", default="music-toolbar")
    parser.add_argument("--stock-id", default="omarchy.media")
    parser.add_argument("--section", choices=SECTIONS, default="center")
    args = parser.parse_args()

    try:
        config, mode = load_config(args.config, args.template)
        if args.action == "enable":
            enable(config, args.plugin_id, args.stock_id, args.state, args.section)
        else:
            disable(config, args.plugin_id, args.stock_id, args.state)
        atomic_write_json(args.config, config, mode)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"Music Toolbar bar configuration error: {error}\n")
    print(f"Updated {args.config} for {args.plugin_id} ({args.action}).")


if __name__ == "__main__":
    main()
