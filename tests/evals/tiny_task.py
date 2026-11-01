"""A four-question task for the eval engine's tests: no download, scored by exact match on the mock model."""
from inspect_ai import Task, task
from inspect_ai.dataset import MemoryDataset, Sample
from inspect_ai.scorer import match
from inspect_ai.solver import generate


@task
def tiny_task():
    qs = [("2+2", "4"), ("3+3", "6"), ("capital of France", "Paris"), ("5*5", "25")]
    return Task(dataset=MemoryDataset([Sample(input=q, target=a) for q, a in qs]), solver=generate(), scorer=match())
