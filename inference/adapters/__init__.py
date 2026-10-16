from .models.object.yolo import ObjectDetectionModel
from .registry import Registry

__all__ = [
    "Registry",
    "ObjectDetectionModel",
]
