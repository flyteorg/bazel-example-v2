import flyte

env = flyte.TaskEnvironment("hi")


@env.task
def say_hi(name: str) -> str:
    return f"Hi! {name}"
