# NOTE: This function contains the code for redis database.
from inference import define

import redis
from typing import Literal

Streams = Literal["REQUEST", "RESULT"]
LATEST = "$"


class Redis:
    # Constructor for initializing
    def __init__(self, host: str = "localhost", port: int = 6379):
        self.host = host
        self.port = port
        self.conn: redis.Redis = redis.Redis(
            host=self.host,
            port=self.port,
            decode_responses=False,
            socket_timeout=None,
            retry_on_timeout=True,
        )

    def ping(self):
        return self.conn.ping()

    def pull_from_stream(self, stream: Streams, last_id=LATEST):
        args = {stream: last_id}
        return self.conn.xread(args, block=5000)

    def write_to_stream(self, stream: Streams, payload: define.ModelResult):
        return self.conn.xadd(stream, {"result": payload})

    def get(self, id: str):
        return self.conn.get(id)
