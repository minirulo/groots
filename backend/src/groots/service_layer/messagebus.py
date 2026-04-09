from dataclasses import dataclass
from typing import Any, Callable, Type

from groots.service_layer.unit_of_work import AbstractUnitOfWork

Command = Any
Handler = Callable


@dataclass
class MessageBus:
    uow: AbstractUnitOfWork
    command_handlers: dict[Type[Command], Handler]

    async def handle(self, command: Command) -> Any:
        handler = self.command_handlers[type(command)]
        return await handler(command, self.uow)
