import flyte

from package.hello import say_hi

env = flyte.TaskEnvironment("test")


@env.task
async def main(x: str) -> str:
    response = await say_hi(x)
    return f"The Python package says, '{response}'"



def entrypoint():
   flyte.init()
   r = flyte.run(main, "Bazel")
   print(r.url)
   print(r.outputs())


if __name__ == "__main__":
   entrypoint()
