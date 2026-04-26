from render_worker.worker import RenderJob, RenderWorker


def main() -> None:
    worker = RenderWorker()
    worker.enqueue(RenderJob(id="m0-job-1", kind="clip", payload={"mode": "stub"}))
    worker.run_once()


if __name__ == "__main__":
    main()
