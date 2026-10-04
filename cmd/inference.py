import asyncio
import logging
import json
import argparse
import time
from dataclasses import asdict

from inference import adapters
from inference import database


def setLogging():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        default="INFO",
    )

    args = parser.parse_args()

    level = getattr(logging, args.log_level)

    logging.basicConfig(level=level, format="%(levelname)-8s: %(message)s")

    return logging.getLogger("cognivision")


# Log stores the logger
log = setLogging()


def build() -> adapters.Registry:
    """Build Registry creates and loads all the models"""

    registry = adapters.Registry()
    detectionModel = adapters.ObjectDetectionModel("yolo26n.pt")

    registry.register(detectionModel)
    registry.load()

    return registry


async def run() -> None:

    # get the database and check the connection.
    db = database.Redis()
    if not db.ping():
        raise RuntimeError("unable to ping database")

    registry = build()
    log.info("loaded models: %s", registry.available_models())

    log.debug("initiating read from stream")

    return await read(db, registry)


async def read(db: adapters.Redis, registry: adapters.Registry) -> None:
    # get all the new entries from now on
    last_id = "$"

    while True:
        entries = db.pull_from_stream("REQUEST", last_id=last_id)
        if not entries:
            continue

        log.debug(f"recieved {len(entries)} new requests")

        _, messages = entries[0]
        for redis_id, fields in messages:
            last_id = redis_id

            # Get the request JSON from the stream
            raw_request = fields[b"request"]

            request = json.loads(raw_request)

            # This is your UUID/key, NOT the Redis stream message ID
            uuid = request["id"]
            prompt = request["prompt"]

            # Get image using your UUID
            img = db.get(uuid)

            if img is None:
                log.warning("no image found: id: %s, dropping request.", uuid)
                continue

            log.debug("fetched image with size %d bytes from store.", len(img))

            s = time.perf_counter()
            r = await registry.detect("yolo26n.pt", img)
            time_taken = time.perf_counter() - s

            r.id = uuid
            r.prompt = prompt

            json_result = json.dumps(asdict(r))

            inference = json.loads(r.inference)

            log.info(
                "INFERENCE[%s][%.3f]: %s",
                redis_id,
                time_taken,
                json.dumps(inference, indent=2),
            )

            db.write_to_stream("RESULT", json_result)

            log.debug("wrote %d bytes to database.", len(json_result.encode()))


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        log.info("shutting down inference server")
