from __future__ import annotations

from dataclasses import dataclass
from queue import Empty, Queue
from threading import Event
import os
import json
from time import sleep
from typing import Any

import httpx
from redis import Redis


@dataclass(slots=True)
class RenderJob:
    id: str
    kind: str
    payload: dict[str, Any]


class RenderWorker:
    def __init__(self) -> None:
        self.jobs: Queue[RenderJob] = Queue()
        self.stop_event = Event()
        self.redis_url = os.getenv("CINEFUSE_REDIS_URL", os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"))
        self.redis_queue = os.getenv("CINEFUSE_RENDER_QUEUE_KEY", "cinefuse:render_jobs")
        self.gateway_url = os.getenv("CINEFUSE_API_BASE_URL", "http://localhost:4000")
        self.worker_token = os.getenv("CINEFUSE_WORKER_TOKEN", "cinefuse-dev-worker-token")

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
            if not self.run_once() and not self.run_once_redis():
                sleep(0.2)

    def shutdown(self) -> None:
        self.stop_event.set()

    def _process(self, job: RenderJob) -> None:
        print(
            f"[render-worker] processed stub job id={job.id} kind={job.kind} payload={job.payload}"
        )

    def run_once_redis(self) -> bool:
        redis_client = Redis.from_url(self.redis_url, decode_responses=True)
        result = redis_client.blpop(self.redis_queue, timeout=1)
        if not result:
            return False

        _, payload = result
        task = json.loads(payload)
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                f"{self.gateway_url}/api/v1/internal/render/process",
                headers={"x-cinefuse-worker-token": self.worker_token},
                json=task,
            )
            response.raise_for_status()
        return True
