from dataclasses import dataclass

@dataclass
class ObjectDetection:
    # label is the name of object
    label: str
    # bbox contains the bounding boxes of object
    bbox: tuple[int, int, int, int] | None = None

available_models = {
    "YOLO_NANO": "yolo26n.pt"
}