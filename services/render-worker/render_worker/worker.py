from __future__ import annotations

from dataclasses import dataclass
from queue import Empty, Queue
from threading import Event
from time import sleep
from typing import Any


@dataclass(slots=True)
class RenderJob:
    id: str
    kind: str
    payload: dict[str, Any]


class RenderWorker:
    def __init__(self) -> None:
        self.jobs: Queue[RenderJob] = Queue()
        self.stop_event = Event()

    def enqueue(self, job: RenderJob) -> None:
        self.jobs.put(job)

    def run_once(self) -> bool:
        try:
            job = self.jobs.get_nowait()
            self._process(job)
            return True
        except Empty:
            return False

    def run_forever(self) -> None:
        while not self.stop_event.is_set():
            if not self.run_once():
                sleep(0.2)

    def shutdown(self) -> None:
        self.stop_event.set()

    def _process(self, job: RenderJob) -> None:
        print(
            f"[render-worker] processed stub job id={job.id} kind={job.kind} payload={job.payload}"
        )
