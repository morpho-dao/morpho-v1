// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library Types {
    /// ENUMS ///

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /// STRUCTS ///

    struct Params {
        uint256 supplyP2pExchangeRate;
        uint256 borrowP2pExchangeRate;
        uint256 poolSupplyExchangeRate;
        uint256 poolBorrowExchangeRate;
        uint256 lastPoolSupplyExchangeRate;
        uint256 lastPoolBorrowExchangeRate;
        uint256 reserveFactor;
        Delta delta;
    }

    struct Delta {
        uint256 supplyP2PDelta; // Difference between the stored P2P supply amount and the real P2P supply amount (in scaled balance).
        uint256 borrowP2PDelta; // Difference between the stored P2P borrow amount and the real P2P borrow amount (in adUnit).
        uint256 supplyP2PAmount; // Sum of all stored P2P supply (in P2P unit).
        uint256 borrowP2PAmount; // Sum of all stored P2P borrow (in P2P unit).
    }

    struct LastPoolIndexes {
        uint256 lastSupplyPoolIndex; // Last supply pool index (current exchange rate) stored.
        uint256 lastBorrowPoolIndex; // Last borrow pool index (borrow index) stored.
    }

    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Compound. Multiply by current borrowIndex to get the underlying amount.
    }

    // Max gas to consume for supply, borrow, withdraw and repay functions.
    struct MaxGas {
        uint64 supply;
        uint64 borrow;
        uint64 withdraw;
        uint64 repay;
    }

    struct AssetLiquidityData {
        uint256 collateralValue; // The collateral value of the asset.
        uint256 maxDebtValue; // The maximum possible debt value of the asset.
        uint256 debtValue; // The debt value of the asset.
        uint256 underlyingPrice; // The price of the token.
        uint256 collateralFactor; // The liquidation threshold applied on this token (in basis point).
    }

    struct LiquidityData {
        uint256 collateralValue; // The collateral value.
        uint256 maxDebtValue; // The maximum debt value possible.
        uint256 debtValue; // The debt value.
    }

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 borrowBalance;
        uint256 supplyBalance;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 amountToSeize;
    }
}
