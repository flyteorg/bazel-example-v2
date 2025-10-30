# Add few more bazel rules
1. Add support for flyte_run target  - takes a task function. Also takes mode - local vs remote. It should ideally allow passing parameters - we can work on this by using some module from flyte
2. Add support for flyte_deploy target - takes a env that we can deploy
3. Add support for flyte_build that takes an env
