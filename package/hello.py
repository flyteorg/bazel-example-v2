import flyte

env = flyte.TaskEnvironment("hi")


@env.task
async def say_hi(name: str, count: int) -> str:
    return f"Hi! {name} (repeated {count} times)"
