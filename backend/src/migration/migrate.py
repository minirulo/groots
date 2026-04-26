import argparse
import logging
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path

from groots.config import settings
from mako.template import Template
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATETIME_FORMAT = "%Y%m%d"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Groots Mongo migration engine.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    new_parser = subparsers.add_parser("new", help="Create a new migration file")
    new_parser.add_argument(
        "--name", type=str, required=True, help="Name of the new migration"
    )

    subparsers.add_parser("migrate", help="Migrate to a specific version").add_argument(
        "--version",
        type=str,
        help="Target version in YYYYMMDD format. Defaults to today.",
    )

    return parser.parse_args()


def wait_for_mongo(client: MongoClient) -> None:
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            client.is_mongos
            return
        except ServerSelectionTimeoutError:
            time.sleep(1)
    raise TimeoutError("MongoDB is not reachable")


def create_new_migration(message: str, version: str) -> None:
    new_migration = Template(filename="migration.py.mako").render(
        message=message, create_date=version
    )
    name = message.lower().replace(" ", "_")
    path = f"versions/{version}_{name}.py"
    with open(path, "w") as f:
        f.write(new_migration)
    logger.info("Created %s", path)


def get_current_version(client: MongoClient) -> datetime:
    doc = client[settings.MONGO_DB]["version"].find_one()
    return doc["version"] if doc else datetime.min


def set_current_version(client: MongoClient, version: datetime) -> None:
    client[settings.MONGO_DB]["version"].update_one(
        {}, {"$set": {"version": version}}, upsert=True
    )


def migrate(client: MongoClient, version: str) -> None:
    scripts_dir = Path(__file__).parent / "versions"
    scripts = sorted(os.listdir(scripts_dir))
    current = get_current_version(client)
    target = datetime.strptime(version, DATETIME_FORMAT)

    for script in scripts:
        if not script.endswith(".py"):
            continue
        script_version = datetime.strptime(script.split("_")[0], DATETIME_FORMAT)
        if current < script_version <= target:
            script_path = str(scripts_dir / script)
            logger.info("Applying %s", script)
            subprocess.run(["python3", script_path], check=True)
            set_current_version(client, script_version)
            logger.info("Version advanced to %s", script_version.strftime(DATETIME_FORMAT))
            logger.info("##########################")


if __name__ == "__main__":
    args = parse_arguments()
    if args.command == "new":
        create_new_migration(args.name, datetime.now().strftime(DATETIME_FORMAT))
    elif args.command == "migrate":
        client = MongoClient(settings.MONGO_DB_URI)
        wait_for_mongo(client)
        migrate(
            client=client,
            version=getattr(args, "version", None) or datetime.now().strftime(DATETIME_FORMAT),
        )
