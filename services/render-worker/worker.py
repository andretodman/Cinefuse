from render_worker.worker import RenderJob, RenderWorker


def main() -> None:
    worker = RenderWorker()
    worker.enqueue(RenderJob(id="warmup-job", kind="clip", payload={"mode": "warmup"}))
    worker.run_once()
    worker.run_forever()


if __name__ == "__main__":
    main()
