import flyte

env = flyte.TaskEnvironment("hi")


@env.task
async def say_hi(name: str) -> str:
    return f"Hi! {name}"
