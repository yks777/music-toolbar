#!/usr/bin/env python3
"""Bounded no-follow preference storage and atomic fixed CAVA config staging."""

import argparse
import configparser
import json
import os
import secrets
import stat
import sys

MAX_CONFIG_BYTES = 65536
MAX_CAVA_CONFIG_BYTES = 16384
VALID_STYLES = {"wave", "bars", "dots"}
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW


def _open_directory_chain(path, create=False):
    """Open each path component as a directory without following symlinks."""
    absolute = os.path.abspath(path)
    directory_fd = os.open(os.path.sep, DIRECTORY_FLAGS)
    try:
        for component in (part for part in absolute.split(os.path.sep) if part):
            try:
                next_fd = os.open(component, DIRECTORY_FLAGS, dir_fd=directory_fd)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(component, mode=0o700, dir_fd=directory_fd)
                except FileExistsError:
                    pass
                next_fd = os.open(component, DIRECTORY_FLAGS, dir_fd=directory_fd)
            info = os.fstat(next_fd)
            if not stat.S_ISDIR(info.st_mode):
                os.close(next_fd)
                raise OSError(f"refusing to use a non-directory path component: {component}")
            os.close(directory_fd)
            directory_fd = next_fd
        return directory_fd
    except BaseException:
        os.close(directory_fd)
        raise


def _split_path(path):
    absolute = os.path.abspath(path)
    name = os.path.basename(absolute)
    if name in ("", ".", ".."):
        raise ValueError("settings path must name a file")
    return os.path.dirname(absolute), name


def _open_regular_no_follow(path):
    directory, name = _split_path(path)
    directory_fd = _open_directory_chain(directory)
    try:
        fd = os.open(name, FILE_FLAGS, dir_fd=directory_fd)
    finally:
        os.close(directory_fd)

    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(f"refusing to use a non-regular settings file: {path}")
        if info.st_size > MAX_CONFIG_BYTES:
            raise OSError(f"refusing to use an oversized settings file: {path}")
        return fd, stat.S_IMODE(info.st_mode)
    except BaseException:
        os.close(fd)
        raise


def _read_bounded(fd, path):
    limit = MAX_CONFIG_BYTES + 1
    chunks = []
    total = 0
    while total < limit:
        chunk = os.read(fd, min(8192, limit - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    if total > MAX_CONFIG_BYTES:
        raise OSError(f"refusing to read an oversized settings file: {path}")
    return b"".join(chunks).decode("utf-8")


def check_file(path):
    try:
        fd, _ = _open_regular_no_follow(path)
    except FileNotFoundError:
        return
    try:
        _read_bounded(fd, path)
    finally:
        os.close(fd)


def _validated_settings(raw):
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_CONFIG_BYTES:
        raise ValueError("settings payload exceeds the configured size limit")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("settings must be a JSON object")

    style = value.get("visualizerStyle", "wave")
    player_key = value.get("selectedPlayerKey", "")
    if not isinstance(style, str) or style not in VALID_STYLES:
        style = "wave"
    if not isinstance(player_key, str):
        player_key = ""
    player_key = "".join(ch for ch in player_key.lower() if ch.isascii() and ch.isalnum())[:128]

    def boolean_setting(name, default):
        candidate = value.get(name, default)
        return candidate if isinstance(candidate, bool) else default

    return {
        "visualizerStyle": style,
        "selectedPlayerKey": player_key,
        "showText": boolean_setting("showText", True),
        "showControls": boolean_setting("showControls", False),
        "showPlayerIcon": boolean_setting("showPlayerIcon", True),
        "fullBarCava": boolean_setting("fullBarCava", False),
    }


def read_settings(path):
    """Read and validate preferences from one bounded, no-follow file handle."""
    try:
        fd, _ = _open_regular_no_follow(path)
    except FileNotFoundError:
        return {
            "visualizerStyle": "wave",
            "selectedPlayerKey": "",
            "showText": True,
            "showControls": False,
            "showPlayerIcon": True,
            "fullBarCava": False,
        }
    try:
        return _validated_settings(_read_bounded(fd, path))
    finally:
        os.close(fd)


def _create_temp_file(directory_fd):
    for _ in range(100):
        name = ".music-toolbar." + secrets.token_hex(12) + ".tmp"
        try:
            fd = os.open(
                name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                0o600,
                dir_fd=directory_fd,
            )
            return fd, name
        except FileExistsError:
            continue
    raise OSError("could not create a unique temporary settings file")


def write_settings(path, raw):
    settings = _validated_settings(raw)
    directory, name = _split_path(path)
    directory_fd = _open_directory_chain(directory, create=True)
    temp_name = None
    try:
        existing_mode = None
        try:
            existing_fd = os.open(name, FILE_FLAGS, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
        else:
            try:
                info = os.fstat(existing_fd)
                if not stat.S_ISREG(info.st_mode):
                    raise OSError(f"refusing to replace a non-regular settings file: {path}")
                if info.st_size > MAX_CONFIG_BYTES:
                    raise OSError(f"refusing to replace an oversized settings file: {path}")
                existing_mode = stat.S_IMODE(info.st_mode)
            finally:
                os.close(existing_fd)

        temp_fd, temp_name = _create_temp_file(directory_fd)
        encoded = (json.dumps(settings, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
        with os.fdopen(temp_fd, "wb") as handle:
            handle.write(encoded)
            if existing_mode is not None:
                os.fchmod(handle.fileno(), existing_mode)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temp_name, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        temp_name = None
        os.fsync(directory_fd)
    finally:
        if temp_name is not None:
            try:
                os.unlink(temp_name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        os.close(directory_fd)


def prepare_cava_config(source_path, destination_path):
    """Atomically stage the fixed 96-bar config for CAVA without following links."""
    source_fd, _ = _open_regular_no_follow(source_path)
    try:
        content = _read_bounded(source_fd, source_path).encode("utf-8")
    finally:
        os.close(source_fd)

    if not content or len(content) > MAX_CAVA_CONFIG_BYTES:
        raise ValueError("CAVA configuration is empty or exceeds the configured size limit")
    parsed = configparser.ConfigParser(interpolation=None)
    try:
        parsed.read_string(content.decode("utf-8"))
        if parsed.getint("general", "bars") != 96:
            raise ValueError("CAVA must be configured for exactly 96 bars")
    except (configparser.Error, UnicodeDecodeError, ValueError) as error:
        raise ValueError("CAVA configuration must be valid and specify 96 bars") from error

    directory, name = _split_path(destination_path)
    directory_fd = _open_directory_chain(directory, create=True)
    temp_name = None
    try:
        directory_info = os.fstat(directory_fd)
        if directory_info.st_uid != os.getuid() or stat.S_IMODE(directory_info.st_mode) & 0o022:
            raise OSError("refusing to use an unsafe CAVA runtime directory")

        try:
            existing_fd = os.open(name, FILE_FLAGS, dir_fd=directory_fd)
        except FileNotFoundError:
            existing = None
        else:
            try:
                info = os.fstat(existing_fd)
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                    raise OSError("refusing to replace an unsafe CAVA configuration file")
                if info.st_size > MAX_CAVA_CONFIG_BYTES:
                    raise OSError("refusing to replace an oversized CAVA configuration file")
                existing = _read_bounded(existing_fd, destination_path).encode("utf-8")
            finally:
                os.close(existing_fd)

        if existing == content:
            return False

        temp_fd, temp_name = _create_temp_file(directory_fd)
        with os.fdopen(temp_fd, "wb") as handle:
            handle.write(content)
            os.fchmod(handle.fileno(), 0o600)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temp_name, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        temp_name = None
        os.fsync(directory_fd)
        return True
    finally:
        if temp_name is not None:
            try:
                os.unlink(temp_name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        os.close(directory_fd)


def migrate_settings(source_path, destination_path):
    """One-time move of validated preferences out of the watched plugin dir.

    Returns True when settings were migrated, False when there was nothing
    to do (destination already exists, or no legacy source file).
    """
    try:
        existing_fd, _ = _open_regular_no_follow(destination_path)
        os.close(existing_fd)
        return False
    except FileNotFoundError:
        pass
    try:
        source_fd, _ = _open_regular_no_follow(source_path)
        os.close(source_fd)
    except (FileNotFoundError, OSError):
        return False
    try:
        settings = read_settings(source_path)
    except (OSError, ValueError):
        return False
    write_settings(destination_path, json.dumps(settings))
    return True


def main():
    parser = argparse.ArgumentParser(description="Read or atomically write Music Toolbar settings.")
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--check", action="store_true", help="validate the settings path")
    actions.add_argument("--read", action="store_true", help="read bounded, validated settings as JSON")
    actions.add_argument("--write", action="store_true", help="atomically write settings")
    actions.add_argument(
        "--migrate", nargs=2, metavar=("SOURCE", "DESTINATION"),
        help="copy validated settings from SOURCE to DESTINATION once, without following symlinks",
    )
    actions.add_argument(
        "--prepare-cava", nargs=2, metavar=("SOURCE", "DESTINATION"),
        help="stage the fixed 96-bar CAVA config at startup without following symlinks",
    )
    parser.add_argument("path", nargs="?")
    parser.add_argument("payload", nargs="?")
    args = parser.parse_args()

    try:
        if args.prepare_cava:
            prepare_cava_config(*args.prepare_cava)
        elif args.migrate:
            migrate_settings(*args.migrate)
        else:
            if not args.path:
                parser.error("a settings path is required")
            if args.check:
                check_file(args.path)
            elif args.read:
                print(json.dumps(read_settings(args.path), ensure_ascii=False))
            else:
                if args.payload is None:
                    raise ValueError("a JSON settings payload is required")
                write_settings(args.path, args.payload)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Music Toolbar settings error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
