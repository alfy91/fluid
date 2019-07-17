# Explorable visualisations for data science

[![CircleCI](https://circleci.com/gh/rolyp/lambdacalc.svg?style=svg&circle-token=c86993fd6b2339b45286ddfc5a4c0c0d2401ffd7)](https://circleci.com/gh/rolyp/lambdacalc)

## Current status

### Forthcoming

| Feature/change | Issue(s) | When |
| --- | --- | --- |
| **Higher-level graphics primitives**<br>Eliminate spurious layout-related dependencies and improve performance | [183](https://github.com/rolyp/lambdacalc/issues/183), [121](https://github.com/rolyp/lambdacalc/issues/121), [180](https://github.com/rolyp/lambdacalc/issues/180), [112](https://github.com/rolyp/lambdacalc/issues/112) | August |
| **Wrattler integration** | [193](https://github.com/rolyp/lambdacalc/issues/193), [192](https://github.com/rolyp/lambdacalc/issues/192), [55](https://github.com/rolyp/lambdacalc/issues/55) | September |

### Recently completed

| Feature/change | Issue(s) | When |
| --- | --- | --- |
| **Migrate to Nearley parser**<br>Improved error-reporting | [190](https://github.com/rolyp/lambdacalc/issues/190) | 29 June 2019 | 
| **Preliminary design for linking visualisations** | [164](https://github.com/rolyp/lambdacalc/issues/164), [188](https://github.com/rolyp/lambdacalc/issues/188) | 18 June 2019 |
| **Library code for axes** | [53](https://github.com/rolyp/lambdacalc/issues/53), [111](https://github.com/rolyp/lambdacalc/issues/111) | 10 June 2019 |

## Possible submissions

| Venue            | Deadline    |
| ---------------- |:-----------:|
| ICFP 2020        | ~1 Mar 2020 |
| Eurovis 2020     | 5 Dec 2019  |
| <s>LIVE 2019</s> | 2 Aug 2019  |

## Installation

- Ensure you have a recent version of [nodejs](https://nodejs.org/en/download/current/). Then run `npm install`.

- To run the tests in debug mode with Chrome, run `karma start --browsers=Chrome --singleRun=false`.

- To start the UI, run `npm start` and open a browser at http://localhost:8080/webpack-dev-server/.

![LambdaCalc](http://i.imgur.com/ERSxpE0.png "LambdaCalc")
