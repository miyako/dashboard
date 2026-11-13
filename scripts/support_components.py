"""Stage pinned, separately installed support components for real 4D checks."""
import hashlib
import io
import json
import re
from pathlib import Path, PurePosixPath
import shutil
import stat
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile


def _regular(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("support component paths must not traverse symlinks")


def _entries(archive, prefix=None):
    seen = set()
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if (entry.filename in seen or path.is_absolute() or ".." in path.parts
                or "\\" in entry.filename or not path.parts
                or (prefix is not None and path.parts[0] != prefix)):
            raise ValueError("unsafe support component archive path")
        seen.add(entry.filename)
        mode = entry.external_attr >> 16
        if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError("support component archive contains a special entry")
        yield entry


def _download(url, path):
    def check_url(value):
        parsed = urlsplit(value)
        if (parsed.scheme != "https" or parsed.hostname not in {
                "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}
                or parsed.username is not None or parsed.password is not None
                or parsed.port not in (None, 443)):
            raise ValueError("untrusted support component download redirect")

    class Redirects(HTTPRedirectHandler):
        def redirect_request(self, request, file, code, message, headers, new_url):
            check_url(new_url)
            return super().redirect_request(request, file, code, message, headers, new_url)

    check_url(url)
    with build_opener(Redirects()).open(
            Request(url, headers={"User-Agent": "dashboard-component-acceptance"}), timeout=30) as response:
        content = response.read(32 * 1024 * 1024 + 1)
    if len(content) > 32 * 1024 * 1024:
        raise ValueError("support component archive exceeds its download bound")
    path.write_bytes(content)


def expected(root):
    root = Path(root)
    lock = root / "support-components.json"
    if not lock.exists():
        return []
    _regular(lock)
    config = json.loads(lock.read_text())
    if (set(config) != {"schema", "components"} or type(config.get("schema")) is not int
            or config["schema"] != 1 or not isinstance(config.get("components"), list)
            or not config["components"]):
        raise ValueError("invalid support component lock")
    names = set()
    for component in config["components"]:
        if (not isinstance(component, dict)
                or set(component) != {"name", "repository", "tag", "revision", "sha256"}):
            raise ValueError("invalid support component fields")
        name = component["name"]
        if (not isinstance(name, str) or name not in ("workers", "tcp") or name in names
                or component["repository"] != "miyako/" + name
                or not isinstance(component["tag"], str)
                or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", component["tag"])
                or not isinstance(component["revision"], str)
                or not re.fullmatch(r"[0-9a-f]{40}", component["revision"])
                or not isinstance(component["sha256"], str)
                or not re.fullmatch(r"[0-9a-f]{64}", component["sha256"])):
            raise ValueError("unsupported or unpinned support component identity")
        names.add(name)
    return [{**component, "compiled": True} for component in config["components"]]


def validate_evidence(root, report):
    components = expected(root)
    if components:
        actual = report.get("support_components")
        if (actual != components or not isinstance(actual, list)
                or any(item.get("compiled") is not True for item in actual)):
            raise ValueError("pinned compiled support component evidence does not match")


def stage(root, destination):
    root = Path(root).resolve()
    components = expected(root)
    if not components:
        return []
    cache = root / ".tools" / "support"
    _regular(cache)
    cache.mkdir(parents=True, exist_ok=True)
    destination = Path(destination)
    _regular(destination)
    destination.mkdir(parents=True, exist_ok=True)
    evidence = []
    for component in components:
        name = component["name"]
        if name not in ("workers", "tcp") or component["repository"] != "miyako/" + name:
            raise ValueError("unsupported support component identity")
        archive_path = cache / (name + "-" + component["tag"] + ".zip")
        _regular(archive_path)
        if not archive_path.exists():
            _download("https://github.com/" + component["repository"] + "/releases/download/"
                      + component["tag"] + "/" + name + ".zip", archive_path)
        content = archive_path.read_bytes()
        if hashlib.sha256(content).hexdigest() != component["sha256"]:
            raise ValueError("support component archive hash mismatch: " + name)
        package_name = name + ".4dbase"
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            entries = list(_entries(archive, package_name))
            packed = archive.read(package_name + "/" + name + ".4DZ")
            with zipfile.ZipFile(io.BytesIO(packed)) as inner:
                inner_entries = list(_entries(inner))
                if (any(entry.filename.endswith(".4dm") for entry in inner_entries)
                        or not any("CompiledCode" in entry.filename for entry in inner_entries)):
                    raise ValueError("support component is not source-stripped compiled code: " + name)
            if not any(entry.filename.endswith("Libraries/lib4d-arm64.dylib") for entry in entries):
                raise ValueError("support component lacks its compiled macOS library: " + name)
            package = destination / package_name
            _regular(package)
            if package.exists():
                for path in package.rglob("*"):
                    _regular(path)
                shutil.rmtree(package)
            for entry in entries:
                output = destination / entry.filename
                if entry.is_dir():
                    output.mkdir(parents=True, exist_ok=True)
                else:
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(archive.read(entry))
                    output.chmod((entry.external_attr >> 16) & 0o777 or 0o644)
        evidence.append(component)
    return evidence
