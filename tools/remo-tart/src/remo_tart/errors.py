"""Typed exceptions for remo-tart. Every error may carry a next-step hint."""


class RemoTartError(Exception):
    """Base exception for remo-tart failures.

    The ``hint`` field should name the command or action the user should
    take next. It is rendered by ``console.render_error``.
    """

    def __init__(self, message: str, *, hint: str | None = None) -> None:
        super().__init__(message)
        self.hint = hint
