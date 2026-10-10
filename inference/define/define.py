from abc import ABC, abstractmethod
from typing import Generic, TypeVar, Literal

AvailableModels = Literal["yolo26n.pt"]

T = TypeVar("T")

class InferenceModel(ABC, Generic[T]):
    """InferenceModel represents interface for running inference on images."""

    name: str

    @abstractmethod
    def load(self) -> None:
        """Load loads the model weights into the memory, should be called once at stratup"""
        raise NotImplementedError

    @abstractmethod
    async def detect(self, img: bytes) -> T:
        """detect runs inference on provided image and returns structured result."""
        raise NotImplementedError

    @abstractmethod
    def is_loaded(self) -> bool:
        """returns true if model is loaded otherwise false."""
        raise NotImplementedError
