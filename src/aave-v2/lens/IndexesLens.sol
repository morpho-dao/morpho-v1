// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/IInterestRatesManager.sol";
import "../interfaces/lido/ILido.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using WadRayMath for uint256;

    /// EXTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyIndex)
    {
        (, p2pSupplyIndex, , ) = _getSupplyIndexes(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        external
        view
        returns (uint256 p2pBorrowIndex)
    {
        (, p2pBorrowIndex, , ) = _getBorrowIndexes(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        (, p2pSupplyIndex, p2pBorrowIndex, poolSupplyIndex, poolBorrowIndex) = _getIndexes(
            _poolToken
        );
    }

    /// INTERNAL ///

    /// @notice Returns the updated pool & peer-to-peer indexes.
    /// @param _poolToken The address of the market.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getIndexes(address _poolToken)
        internal
        view
        returns (
            address underlyingToken,
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.Market memory market = morpho.market(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);
        underlyingToken = market.underlyingToken;

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolToken),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount
            })
        );
        p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolToken),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount
            })
        );
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return market The market from which to compute the peer-to-peer supply index.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getSupplyIndexes(address _poolToken)
        internal
        view
        returns (
            Types.Market memory market,
            uint256 p2pSupplyIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        market = morpho.market(_poolToken);
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolToken),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount
            })
        );
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return market The market from which to compute the peer-to-peer borrow index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getBorrowIndexes(address _poolToken)
        internal
        view
        returns (
            Types.Market memory market,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        market = morpho.market(_poolToken);
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolToken),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount
            })
        );
    }

    /// @notice Returns the current pool indexes.
    /// @param _underlyingToken The address of the underlying token.
    /// @return poolSupplyIndex The pool supply index.
    /// @return poolBorrowIndex The pool borrow index.
    function _getPoolIndexes(address _underlyingToken)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        poolSupplyIndex = pool.getReserveNormalizedIncome(_underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(_underlyingToken);

        if (_underlyingToken == ST_ETH) {
            uint256 rebaseIndex = ILido(ST_ETH).getPooledEthByShares(WadRayMath.RAY);

            poolSupplyIndex = poolSupplyIndex.rayMul(rebaseIndex).rayDiv(ST_ETH_BASE_REBASE_INDEX);
            poolBorrowIndex = poolBorrowIndex.rayMul(rebaseIndex).rayDiv(ST_ETH_BASE_REBASE_INDEX);
        }
    }
}
