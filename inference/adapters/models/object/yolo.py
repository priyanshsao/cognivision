from inference import define
import inference.proto.define_pb2 as types

from ultralytics import YOLO
import cv2
import numpy as np
import base64
import logging

log = logging.getLogger("cognivision")


class ObjectDetectionModel(define.InferenceModel[list[types.ObjectDetectionData]]):
    "ObjectDetectionModel is responsible for detecting objects in an image"

    def __init__(self, name: define.AvailableModels):
        self.name = name
        self._engine: YOLO | None = None

    def load(self) -> None:
        self._engine = YOLO(self.name)
        self._engine.to("cpu")

    def is_loaded(self) -> bool:
        return self._engine is not None

    async def detect(self, img: bytes) -> list[types.ObjectDetectionData]:

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
        final_result: list[types.ObjectDetectionData] = []

        for r in results:
            # Loop over the detected objects
            for box in r.boxes:
                # get the bounding coordinates
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())

                # get class value and extract label
                label = self._engine.names[int(box.cls[0])]

                # one of the result
                result = types.ObjectDetectionData(label=label, bbox=(x1, y1, x2, y2))

                # store in our data structure
                final_result.append(result)

        return final_result
