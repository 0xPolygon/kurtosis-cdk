import importlib
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess

CHECKS_DIR = Path(__file__).resolve().parent / "checks"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)


def discover_checks():
    return [
        f
        for f in CHECKS_DIR.iterdir()
        if f.is_file() and f.suffix in (".py", ".sh") and not f.name.startswith("_")
    ]


def run_check(path):
    try:
        match path.suffix:
            case ".py":
                mod = importlib.import_module(f"{CHECKS_DIR.name}.{path.stem}")
                ok = mod.main()
            case ".sh":
                proc = subprocess.run(
                    ["bash", str(path)], capture_output=True, text=True
                )
                ok = proc.returncode == 0
                stdout = proc.stdout.strip()
                stderr = proc.stderr.strip()
                output = "\n".join(filter(None, [stdout, stderr]))
                logging.debug(f"{path.name}: {output}")
            case _:
                ok = False
                logging.error(f"File type {path.suffix} is not supported")
        return (path.name, ok)
    except Exception as e:
        logging.error(f"{e}")
        return (path.name, False)


def main():
    checks = discover_checks()
    if not checks:
        logging.warning(f"No checks found in {CHECKS_DIR.resolve()}")
        return

    results = []
    with ThreadPoolExecutor() as executor:
        futures = [executor.submit(run_check, check) for check in checks]
        for f in futures:
            results.append(f.result())

    for check, ok in results:
        status = "✅" if ok else "❌"
        logging.info(f"{check}: {status}")


if __name__ == "__main__":
    main()
