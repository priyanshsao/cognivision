import asyncio
import logging
import argparse

from inference import adapters
from inference import database
import inference.proto.define_pb2 as types


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


async def read(db: database.Redis, registry: adapters.Registry) -> None:
    # get all the new entries from now on
    last_id = "$"

    while True:
        entries = db.pull_from_stream("REQUEST", last_id=last_id)
        if not entries:
            continue

        # Todo: change this to info.
        log.debug(f"recieved {len(entries)} new requests")

        _, messages = entries[0]
        for redis_id, fields in messages:
            last_id = redis_id

            request_bytes = fields[b"request"]

            request = types.RedisRequest()
            request.ParseFromString(request_bytes)

            # This is uuid of request, NOT the Redis stream message ID.
            id = request.id
            prompt = request.prompt

            # Get image using your request ID.
            inferencing_img = db.get(id)

            if inferencing_img is None:
                log.warning("no image found for result with id: %s, dropping request.", id)
                continue

            log.debug("fetched image with size %d bytes from store.", len(inferencing_img))

            inference_result = types.InferenceResult()
            inference = types.Inference()
            detections = types.Detections()

            r = await registry.detect("yolo26n.pt", inferencing_img)

            detections.object.extend(r)

            # Todo: implement this using opencv
            # for now leaving this empty 
            inference.img = b""
            
            inference.detections.CopyFrom(detections)

            inference_result.id = id
            inference_result.inference.CopyFrom(inference)
            inference_result.prompt = prompt

            log.debug("generated inference result: %s", inference_result)

            payload = inference_result.SerializeToString()
            db.write_to_stream("RESULT", payload)

            log.debug("successfully sent %d bytes to database.", len(payload))


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        log.info("shutting down inference server.")
