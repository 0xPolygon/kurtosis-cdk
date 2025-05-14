import importlib
import configparser
import subprocess
import threading
import time
from pathlib import Path
import argparse
from dataclasses import dataclass
from typing import Dict
from loguru import logger
import sys


@dataclass
class CheckConfig:
    enabled: bool
    interval: int


@dataclass
class Config:
    enabled_by_default: bool
    pretty_logs: bool
    interval: int
    checks_dir: Path
    checks: Dict[str, CheckConfig]


def load_logger(pretty_logs: bool):
    logger.remove()
    logger.add(
        sys.stderr,
        format="<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
        "<level>{level: <8}</level> | "
        "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - "
        "<level>{message}</level> | "
        "<level>{extra}</level>",
        colorize=pretty_logs,
        serialize=not pretty_logs,
    )


def load_config(config_path: Path) -> Config:
    parser = configparser.ConfigParser()
    parser.read(config_path)

    default_section = parser["default"]
    enabled_by_default = default_section.getboolean("enabled_by_default", fallback=True)
    pretty_logs = default_section.getboolean("pretty_logs", fallback=True)
    interval = default_section.getint("interval", fallback=30)
    default_checks_dir = Path(__file__).resolve().parent / "checks"
    checks_dir = Path(
        default_section.get("checks_dir", str(default_checks_dir))
    ).resolve()

    checks = {}
    for section in parser.sections():
        if section == "default":
            continue
        enabled = parser.getboolean(section, "enabled", fallback=enabled_by_default)
        interval = parser.getint(section, "interval", fallback=interval)
        checks[section] = CheckConfig(enabled=enabled, interval=interval)

    return Config(
        enabled_by_default=enabled_by_default,
        pretty_logs=pretty_logs,
        interval=interval,
        checks_dir=checks_dir,
        checks=checks,
    )


def discover_checks(checks_dir: Path):
    return [
        f
        for f in checks_dir.iterdir()
        if f.is_file() and f.suffix in (".py", ".sh") and not f.name.startswith("_")
    ]


@logger.catch
def run_check(path: Path):
    try:
        if path.suffix == ".py":
            mod = importlib.import_module(f"{path.parent.name}.{path.stem}")
            ok = mod.main()
        elif path.suffix == ".sh":
            proc = subprocess.run(["bash", str(path)], capture_output=True, text=True)
            ok = proc.returncode == 0
            stdout = proc.stdout.strip()
            stderr = proc.stderr.strip()
            output = "\n".join(filter(None, [stdout, stderr]))
            if output:
                logger.bind(check=path.name).debug(output)
        else:
            ok = False
            logger.bind(check=path.name).error(f"Unsupported file type {path.suffix}")
        return (path.name, ok)
    except Exception as e:
        logger.bind(check=path.name).exception(f"Exception occurred: {e}")
        return (path.name, False)


def run_check_loop(path: Path, interval: int):
    while True:
        name, ok = run_check(path)
        status = "✅" if ok else "❌"
        logger.bind(check=name).info(status)
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(
        description="Network monitoring with fault assertions."
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parent / "config.ini",
        help="Path to the config file (default: ./config.ini)",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    load_logger(config.pretty_logs)

    checks = discover_checks(config.checks_dir)

    if not checks:
        logger.warning(f"No checks found in {config.checks_dir}")
        return

    threads = []

    for check_path in checks:
        check_name = check_path.name
        check_conf = config.checks.get(
            check_name,
            CheckConfig(
                enabled=config.enabled_by_default,
                interval=config.interval,
            ),
        )

        if not check_conf.enabled:
            logger.debug(f"{check_name} is disabled, skipping")
            continue

        thread = threading.Thread(
            target=run_check_loop, args=(check_path, check_conf.interval), daemon=False
        )
        thread.start()
        threads.append(thread)

    try:
        for thread in threads:
            thread.join()
    except KeyboardInterrupt:
        logger.info("Stopping...")


if __name__ == "__main__":
    main()
