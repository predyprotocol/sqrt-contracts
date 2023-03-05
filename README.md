predy-v3.2
=====

![](https://github.com/predyprotocol/sqrt-contracts/workflows/test/badge.svg)

## Overview

Predy V3.2 is a smart contract that enables the trading of derivative products called "Squart" on the Ethereum Virtual Machine. Squart is a perpetual future that has gamma and it utilizes Uniswap's LP position. At the same time, Predy provides an easier and more capital-efficient way to utilize Uniswap LPs.

### Squart

Squart is a perpetual contract indexed to $ \sqrt{x} $ of underlying price which enable us to trade gamma.
Predy offers Squart perpetual trading by supplying and borrowing Uniswap V3's LP positions.

## Development

Testing

'''
forge test
'''
