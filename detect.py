import redis
from ultralytics import YOLO
import cv2
import numpy as np
import base64
import json
from pathlib import Path

r = redis.Redis(
    host="localhost",
    port=6379,
    decode_responses=False,
    socket_timeout=None,
    retry_on_timeout=True,
)

model = YOLO(Path(__file__).with_name("yolo26n.pt"))

last_id = "$"

while True:
    result = r.xread(
        {
            "REQUEST": last_id
        },
        block=0
    )

    for stream, messages in result:
        for message_id, data in messages:
            last_id = message_id

            print("received stream message:", message_id)

            # Get the request JSON from the stream
            raw_request = data[b"request"]

            request = json.loads(raw_request)

            # This is your UUID/key, NOT the Redis stream message ID
            request_id = request["id"]
            prompt = request["prompt"]

            print("request id:", request_id)
            print("prompt:", prompt)

            # Get image using your UUID
            img = r.get(request_id)

            if img is None:
                print("no image found")
                continue

            print("image:", len(img), "bytes")

            image = cv2.imdecode(
                np.frombuffer(img, np.uint8),
                cv2.IMREAD_COLOR
            )

            if image is None:
                print("unable to decode image")
                continue

            results = model(image)

            jsonData = results[0].to_json()

            annotated_image = results[0].plot()
            ok, encoded_img = cv2.imencode(".jpg", annotated_image)

            if not ok:
                print("unable to encode image")
                continue

            img_base64 = base64.b64encode(
                encoded_img.tobytes()
            ).decode("utf-8")

            inference_result = {
                "id": request_id,
                "prompt": prompt,
                "img": img_base64,
                "result": jsonData,
            }

            r.xadd(
                "RESULT",
                {
                    "result": json.dumps(inference_result)
                }
            )

            print("result sent")