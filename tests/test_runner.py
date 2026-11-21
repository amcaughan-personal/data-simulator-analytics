from types import SimpleNamespace

import pytest

from runner import handler as runner


class FakeDbt:
    """Records each invocation; fails the commands listed in `failing`."""

    def __init__(self, failing=()):
        self.failing = set(failing)
        self.invocations = []

    def __call__(self):
        return self

    def invoke(self, args):
        self.invocations.append(args)
        return SimpleNamespace(success=args[0] not in self.failing)


@pytest.fixture
def dbt(monkeypatch):
    monkeypatch.setenv("DBT_PROJECT_DIR", "/project")

    def use(failing=()):
        fake = FakeDbt(failing)
        monkeypatch.setattr(runner, "dbtRunner", fake)
        return fake

    return use


def test_the_schedule_checks_freshness_then_builds(dbt):
    fake = dbt()

    assert runner.handler({}, None) == {"source freshness": "succeeded", "build": "succeeded"}
    assert fake.invocations == [
        ["source", "freshness", "--project-dir", "/project", "--profiles-dir", "/project"],
        ["build", "--project-dir", "/project", "--profiles-dir", "/project"],
    ]


def test_stale_sources_still_build_but_fail_the_run(dbt):
    fake = dbt(failing={"source"})

    with pytest.raises(RuntimeError, match="dbt failed: source freshness"):
        runner.handler({}, None)
    assert [args[0] for args in fake.invocations] == ["source", "build"]


def test_an_event_can_run_other_dbt_arguments(dbt):
    fake = dbt()

    runner.handler({"args": ["build", "--full-refresh"]}, None)

    assert fake.invocations == [
        ["build", "--full-refresh", "--project-dir", "/project", "--profiles-dir", "/project"]
    ]


def test_dbt_locks_work_without_shared_memory():
    """Lambda has no /dev/shm; the runner makes multiprocessing hand out thread locks."""
    import multiprocessing

    locks = [multiprocessing.Lock(), multiprocessing.RLock(), multiprocessing.get_context("spawn").RLock()]
    for lock in locks:
        with lock:
            pass
    assert all(type(lock).__module__ in ("_thread", "threading") for lock in locks)
