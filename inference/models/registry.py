from typing import Any

from ..define.classes import Model, ModelResult

class Registry:

    def __init__(self) -> None:
        # create an empty map that will store the available options
        self._models: dict[str, Model[Any]] = {}

    def register(self, model: Model[Any]) -> None:
        self._models[model.name] = model

    def load_all(self) -> None:
        for model in self._models.values():
            if not model.is_loaded:
                model.load()

    async def detect(self, model_name: str, img: bytes) -> ModelResult[Any]:
        model = self._models.get(model_name)
        if model is None:
            raise KeyError(f"'{model_name}' is not registered")

        return await model.detect(img)

    def available_models(self) -> list[str]:
        return list(self._models.keys())