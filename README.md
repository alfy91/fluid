## Fluid: Language-integrated data provenance

(TESTING) Fluid is an experimental programming language which integrates a bidirectional dynamic analysis to connect outputs to data sources in a fine-grained way. Fluid is implemented in PureScript and runs in the browser.

[![develop](https://github.com/explorable-viz/fluid/actions/workflows/develop.yml/badge.svg)](https://github.com/explorable-viz/fluid/actions/workflows/develop.yml)
[![GitHub pages](https://github.com/explorable-viz/fluid/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/explorable-viz/fluid/actions/workflows/pages/pages-build-deployment)
[![v0.3.1-typescript](https://github.com/explorable-viz/fluid/actions/workflows/v0.3.1-typescript.yml/badge.svg)](https://github.com/explorable-viz/fluid/actions/workflows/v0.3.1-typescript.yml)

## Installation
### Software required
- Windows users: Ubuntu (WSL)
- git
- Node.js >=14.0.0
- yarn

### Preconditions
- PureScript is not installed globally
- `Add Npm Path` is selected in PureScript IDE extension settings
- Windows users: 
	- Launch VSCode through Ubuntu (WSL) terminal
	- Installed WSL extension in VSCode

#### Running the tests on the command line

- `yarn build` and then `yarn test` for core tests

#### Running the tests in the browser

- As per command-line tests above, but run `yarn test-browser`
- Hit Debug in the browser window that opens, and then open Developer Tools or equivalent

#### Running the web app
- `yarn build-app`
- `yarn serve-app`
- Open a browser at the served URL (usually `127.0.0.1:8080`)