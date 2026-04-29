from __future__ import annotations

from dataclasses import dataclass
from queue import Empty, Queue
from threading import Event
import json
import logging
import os
from time import sleep
from typing import Any

import httpx
from redis import Redis

logger = logging.getLogger("render_worker")


def _ensure_worker_logging() -> None:
    root = logging.getLogger()
    if root.handlers:
        return
    level_name = (os.getenv("LOG_LEVEL") or "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s [render-worker] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )


@dataclass(slots=True)
class RenderJob:
    id: str
    kind: str
    payload: dict[str, Any]


class RenderWorker:
    def __init__(self) -> None:
        _ensure_worker_logging()
        self.jobs: Queue[RenderJob] = Queue()
        self.stop_event = Event()
        self.redis_url = os.getenv("CINEFUSE_REDIS_URL", os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"))
        self.redis_queue = os.getenv("CINEFUSE_RENDER_QUEUE_KEY", "cinefuse:render_jobs")
        self.gateway_url = os.getenv("CINEFUSE_API_BASE_URL", "http://localhost:4000")
        self.worker_token = os.getenv("CINEFUSE_WORKER_TOKEN", "cinefuse-dev-worker-token")
        self.redis_client: Redis | None = None

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
        # `worker.py` enqueues a warmup RenderJob before Redis BLPOP — not user work, not MCP stub media.
        logger.info(
            "in-process warmup job drained id=%s kind=%s payload=%s",
            job.id,
            job.kind,
            job.payload,
        )

    def run_once_redis(self) -> bool:
        try:
            if self.redis_client is None:
                self.redis_client = Redis.from_url(self.redis_url, decode_responses=True)
            result = self.redis_client.blpop(self.redis_queue, timeout=1)
            if not result:
                return False

            _, payload = result
            task = json.loads(payload)
            job_id = task.get("jobId")
            shot_id = task.get("shotId")
            project_id = task.get("projectId")
            gen_kind = task.get("generationKind", "video")
            logger.info(
                "dequeued queue=%s job_id=%s shot_id=%s project_id=%s kind=%s gateway=%s",
                self.redis_queue,
                job_id,
                shot_id,
                project_id,
                gen_kind,
                self.gateway_url,
            )
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self.gateway_url}/api/v1/internal/render/process",
                    headers={"x-cinefuse-worker-token": self.worker_token},
                    json=task,
                )
                if response.status_code >= 400:
                    body_preview = (response.text or "")[:800]
                    logger.error(
                        "gateway POST /internal/render/process status=%s job_id=%s shot_id=%s body_preview=%r",
                        response.status_code,
                        job_id,
                        shot_id,
                        body_preview,
                    )
                response.raise_for_status()
            logger.info(
                "gateway render ok job_id=%s shot_id=%s project_id=%s",
                job_id,
                shot_id,
                project_id,
            )
            return True
        except Exception:
            logger.exception(
                "redis task failed queue=%s",
                self.redis_queue,
            )
            self.redis_client = None
            return False
