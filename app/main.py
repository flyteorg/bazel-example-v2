import flyte

from package.hello import say_hi

env = flyte.TaskEnvironment("test")


@env.task
async def main(x: str) -> str:
    response = await say_hi(x)
    return f"The Python package says, '{response}'"



def entrypoint(input_str: str = "Bazel"):
   flyte.init()
   r = flyte.run(main, input_str)
   print(r.url)
   print(r.outputs())


if __name__ == "__main__":
   import sys
   # If command line argument provided, use it; otherwise use default
   input_arg = sys.argv[1] if len(sys.argv) > 1 else "Bazel"
   entrypoint(input_arg)
