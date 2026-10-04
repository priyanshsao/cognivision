from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Generic, TypeVar, Literal

AvailableModels = Literal["yolo26n.pt"]

T = TypeVar("T")


@dataclass
class ObjectDetection:
    # label is the name of object
    label: str
    # bbox contains the bounding boxes of object
    bbox: tuple[int, int, int, int] | None = None


@dataclass
class ModelResult(Generic[T]):
    img: str
    inference: T
    id: str = ""
    prompt: str = ""


class InferenceModel(ABC, Generic[T]):
    """InferenceModel represents interface for running inference on images."""

    name: str

    @abstractmethod
    def load(self) -> None:
        """Load loads the model weights into the memory, should be called once at stratup"""
        raise NotImplementedError

    @abstractmethod
    async def detect(self, img: bytes) -> ModelResult[T]:
        """detect runs inference on provided image and returns structured result."""
        raise NotImplementedError

    @abstractmethod
    def is_loaded(self) -> bool:
        """returns true if model is loaded otherwise false."""
        raise NotImplementedError
