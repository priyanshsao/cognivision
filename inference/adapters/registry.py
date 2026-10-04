# NOTE: This file contains the code for registry,
# which is governs all the models for inference.


from typing import Any

from inference import define


class Registry:
    def __init__(self) -> None:
        # create an empty map that will store the available options
        self.models: dict[str, define.InferenceModel[Any]] = {}

    def register(self, model: define.InferenceModel[Any]) -> None:
        """Register registers a model to the registry."""

        self.models[model.name] = model

    def load(self) -> None:
        for model in self.models.values():
            if not model.is_loaded():
                model.load()

    async def detect(
        self, model_name: define.AvailableModels, img: bytes
    ) -> define.ModelResult[Any]:
        model = self.models.get(model_name)

        if model is None:
            raise KeyError(f"'{model_name}' is not registered")

        return await model.detect(img)

    def available_models(self) -> list[str]:
        return list(self.models.keys())
