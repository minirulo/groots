from dataclasses import dataclass, field
from typing import Set
from groots.domain.model.base import new_id


@dataclass
class Role:
    name: str
    id: str = field(default_factory=new_id)
    permissions: Set[str] = field(default_factory=set)
