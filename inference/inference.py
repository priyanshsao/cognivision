import asyncio
import logging

from define import Db, available_models
from models import Registry, ObjectDetectionModel

logging.basicConfig(level=logging.INFO)
logrus = logging.getLogger("cognivision")

REQUEST_STREAM = "REQUEST"
RESULT_STREAM = "RESULT"

def build_registry() -> Registry:
    registry = Registry()
    detectionModel = ObjectDetectionModel(available_models["YOLO_NANO"])

    registry.register(detectionModel)
    registry.load_all()

    return registry

async def run() -> None:
    db = Db()
    if not db.ping():
        raise RuntimeError("unable to ping database")

    registry = build_registry()
    logrus.info("loaded models: %s", registry.available_models())

    # get all the new entries from now on
    last_id = "$"

    while True:
        entries = db.pull_from_stream(REQUEST_STREAM, last_id=last_id)
        if not entries:
            continue

        _, messages  = entries[0]
        for entry_id, fields in messages:
            last_id = entry_id
            img_bytes = fields["image"].encode() if isinstance(fields["image", str]) else fields["image"]

            result = await registry.detect(available_models["YOLO_NANO"], img_bytes)
            i = result.inference.to_json()

            logrus.info("[%s] -> %s", entry_id, result.inference, labels)

            db.write_to_stream(RESULT_STREAM,{"id": entry_id, "result": },)

if __name__ == "__main__":
    asyncio.run(run())