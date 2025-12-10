# Developer Hub

## Helm

All commands should be run from the respository root directory.

When working with a Helm chart from a local checkout, you will need to ensure any dependencies are built:

```shell
helm dependency build charts/${repo_name}
```

This is also true after you update any dependencies to pick them up locally.

### Local Testing

Typically you will first start off with a deployment, we provide a set of [scripts](https://github.com/nscaledev/uni-scripts?) to automate 99% of your day to day tasks.

Deploying is a simple case setting up local configuration and running:

```shell
deploy
```

If that fails due to modifications you have made you can usually debug the template output with:

```shell
deploy -t
```
