Kine Protocol
=================

Kine is a decentralized protocol which establishes general purpose liquidity pools backed by a customizable portfolio of digital assets. The liquidity pool allows traders to open and close derivatives positions according to trusted price feeds, avoiding the need of counterparties. Kine lifts the restriction on existing peer-to-pool (aka peer-to-contract) trading protocols, by expanding the collateral space to any Ethereum-based assets and allowing third-party liquidation.

Kine Protocol allows users to stake ETH and ERC-20 assets as collaterals. Assets staked into the contracts increase the user's debt limit (aka 'liquidation' in codes). Users with unused debt limit can mint kUSD, a synthetic USD-pegging digital asset backed by an over-collateralized liquidity pool. kUSD is the only asset accepted by Kine Exchange, a peer-to-pool derivatives exchange providing multi-asset exposure with zero-slippage trading experience.

Users incur a Multi-Collateralized Debt (MCD) when they mint kUSD, and become part of the pooled counterparty facing traders on Kine Exchange. MCD price may increase or decrease independent of their original minted value, based on the net exposures taken by the liquidity pool. The pool provides liquidity to all trading pairs quoted on Kine Exchange. The exchange accumulates trading fees, and distribute to the pool stakers through ```KUSDMinter``` contract. It also reports the MCD price and adjust kUSD supply through the ```Kaptain``` contract.

Users may repay their MCD debt by burning kUSD, which allows them to withdraw part or full of their staked assets. When a user's debt limit is exceeded (aka 'shortfall' in codes), a 3rd-party liquidator may repay the MCD debt on the user's behalf and seize part of its staking assets with a mark-up.

Docs
=========

Contracts Overview doc can be found [here](./docs/contracts_overview.md)

White paper doc can be found [here](./docs/WhitePaper_Kine_The_Liquidity_Pool_Protocol.pdf)


_© Copyright 2021, Kine Tech_
