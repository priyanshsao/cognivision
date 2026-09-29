from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Generic, TypeVar
import redis

T = TypeVar("T")

@dataclass
class ModelResult(Generic[T]):
    id:         str
    prompt:     str
    img:        str
    inference:  T

class Model(ABC, Generic[T]):
    """Model abstract class represents a model with T representing its result type."""

    name: str

    @abstractmethod
    def load(self) -> None:
      """Load loads the model weights into the memory, should be called once at stratup"""
      raise NotImplementedError
    
    @abstractmethod
    async def detect(self, img: bytes) -> ModelResult[T]:
       """detect runs inference on provided image and returns structured result."""
       raise NotImplementedError
    
    @property
    @abstractmethod
    def is_loaded(self) -> bool:
       """returns true if model is loaded otherwise false."""
       raise NotImplementedError

class Db:
    """Thin wrapper around a redis connection for stream read/write"""

    def __init__(self, host: str = "localhost", port: int = 6379, decode_responses: bool = True):
        self.host: str = host
        self.port: int = port
        self.conn: redis.Redis = redis.Redis(host=self.host, port=self.port, decode_responses=decode_responses, socket_timeout=None, retry_on_timeout=True)

    def ping(self) -> bool:
        """ping checks the connection by pinging the database"""
        return self.conn.ping()
    
    def pull_from_stream(self, stream: str, last_id: str = "$"):
        args = {stream: last_id}
        return self.conn.xread(args, block=None)

    def write_to_stream(self, stream: str, fields: dict) -> str:
        return self.conn.xadd(stream, fields)