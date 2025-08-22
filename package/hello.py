import flyte

env = flyte.TaskEnvironment("hi")


@env.task
def say_hi():
    return "Hi!"
