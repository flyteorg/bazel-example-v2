import flyte

from package.hello import say_hi

env = flyte.TaskEnvironment("test")


@env.task
def main():
    response = say_hi()
    return f"The Python package says, '{response}'"

if __name__ == "__main__":
    main()
