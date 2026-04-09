from dataclasses import asdict
from datetime import datetime

from bson import ObjectId


def new_id() -> str:
    return str(ObjectId())


def model_factory(data: dict) -> dict:
    """Recursively convert domain model types for MongoDB storage."""
    result = {}
    for key, value in data.items():
        if isinstance(value, set):
            result[key] = list(value)
        elif isinstance(value, dict):
            result[key] = model_factory(value)
        else:
            result[key] = value
    return result


def to_document(obj) -> dict:
    """Convert a dataclass to a MongoDB document, mapping id → _id."""
    data = asdict(obj)
    id_val = data.pop("id")
    doc = model_factory(data)
    doc["_id"] = ObjectId(id_val)
    return doc


def from_document(doc: dict, model_cls):
    """Convert a MongoDB document back to a domain model, mapping _id → id."""
    if doc is None:
        return None
    data = dict(doc)
    data["id"] = str(data.pop("_id"))
    return model_cls(**data)
