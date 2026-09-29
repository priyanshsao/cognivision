from define import Model,ModelResult, ObjectDetection,available_models
from ultralytics import YOLO
import cv2
import numpy as np
import base64

class ObjectDetectionModel(Model[ObjectDetection]):
    "ObjectDetectionModel uses yolo to detect objects"

    def __init__(self, name: str = available_models["YOLO_NANO"]):
        self.name = name
        self._runner: YOLO | None = None

    def load(self) -> None:
        self._runner = YOLO(self.name)
        self._runner.to("cpu")

    @property
    def is_loaded(self) -> bool:
        return self._runner is not None

    async def detect(self, id: str, prompt: str,  img: bytes) -> ModelResult[ObjectDetection]:
        # check model is loaded before running
        if self._runner is None:
            raise RuntimeError(f"unable to detect model not loaded: {self.name}")

        buf = np.frombuffer(img, dtype=np.uint8)
        frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("unable to decode image bytes")

        results = self._runner(frame, verbose=False)

        result_final: list[ObjectDetection] = []

        for r in results:
            for box in r.boxes:
                # get the bounding coordinates
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())

                # get class value and extract label
                label = self._runner.names[int(box.cls[0])]

                annotated_image = r.plot()
                ok, encoded_img = cv2.imencode(".jpg", annotated_image)
                if not ok:
                    print("unable to encode image")
                    continue
                
                img = base64.b64encode(encoded_img.tobytes()).decode("utf-8")

                # one of the result
                result = ObjectDetection(label=label, bbox=(x1,y1,x2,y2))

                # store in our data structure
                result_final.append(result)

        return ModelResult(
            id = id,
            prompt = prompt,
            image = img,
            inference= {"detection":result_final},
        )