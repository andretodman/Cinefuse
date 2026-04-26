from pathlib import Path
import sys

sys.path.append(str(Path(__file__).resolve().parents[1]))

from render_worker import RenderJob, RenderWorker


def test_enqueue():
    worker = RenderWorker()
    worker.enqueue(RenderJob(id="1", kind="clip", payload={"x": 1}))
    assert worker.jobs.qsize() == 1


def test_run_once_processes():
    worker = RenderWorker()
    worker.enqueue(RenderJob(id="2", kind="clip", payload={}))
    assert worker.run_once() is True


def test_run_once_redis_handles_connection_failure():
    worker = RenderWorker()
    worker.redis_url = "redis://127.0.0.1:1/0"
    assert worker.run_once_redis() is False
