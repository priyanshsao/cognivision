from inference import define

from ultralytics import YOLO
import cv2
import numpy as np
import base64
import logging
import json
from dataclasses import asdict

log = logging.getLogger("cognivision")


class ObjectDetectionModel(define.InferenceModel[list[define.ObjectDetection]]):
    "ObjectDetectionModel is responsible for detecting objects in an image"

    def __init__(self, name: define.AvailableModels):
        self.name = name
        self._engine: YOLO | None = None

    def load(self) -> None:
        self._engine = YOLO(self.name)
        self._engine.to("cpu")

    def is_loaded(self) -> bool:
        return self._engine is not None

    async def detect(self, img: bytes) -> define.ModelResult[define.ObjectDetection]:
        # check model is loaded before running
        if self._engine is None:
            raise RuntimeError(f"unable to detect model not loaded: {self.name}")

        # convert image bytes to opencv format
        buf = np.frombuffer(img, dtype=np.uint8)
        frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("unable to decode image bytes")

        results = self._engine(frame, verbose=False)

        # create a var for storing result.
        final_result: list[define.ObjectDetection] = []

        for r in results:
            # This gives a plotted output image of form np ndarray.
            annotated_image = r.plot()

            # encode the image into jpg format.
            ok, encoded_img = cv2.imencode(".jpg", annotated_image)
            if not ok:
                log.debug("unable to encode image to JPG.")
                log.warning("unable to process result: dropping result.")
                continue

            # convert to base64
            img = base64.b64encode(encoded_img.tobytes()).decode("utf-8")

            # Loop over the detected objects
            for box in r.boxes:
                # get the bounding coordinates
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())

                # get class value and extract label
                label = self._engine.names[int(box.cls[0])]

                # one of the result
                result = define.ObjectDetection(label=label, bbox=(x1, y1, x2, y2))

                # store in our data structure
                final_result.append(result)

        return define.ModelResult(
            img=img,
            inference=json.dumps([asdict(obj) for obj in final_result]),
        )
