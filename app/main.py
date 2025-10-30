import flyte

from package.hello import say_hi

env = flyte.TaskEnvironment("test")


@env.task
async def main(x: str, count: int) -> str:
    response = await say_hi(x, count)
    return f"The Python package says, '{response}'"



def entrypoint(input_str: str = "Bazel", count: int = 1):
   flyte.init()
   r = flyte.run(main, input_str, count)
   print(r.url)
   print(r.outputs())


if __name__ == "__main__":
   import sys
   # Parse command line arguments: first is string, second is int
   input_str = sys.argv[1] if len(sys.argv) > 1 else "Bazel"
   count = int(sys.argv[2]) if len(sys.argv) > 2 else 1
   entrypoint(input_str, count)
