// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./MorphoUtils.sol";

/// @title MatchingEngine.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract managing the matching engine.
abstract contract MatchingEngine is MorphoUtils {
    using HeapOrdering for HeapOrdering.HeapArray;
    using WadRayMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct UnmatchVars {
        uint256 p2pIndex;
        uint256 toUnmatch;
        uint256 poolIndex;
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        uint256 p2pIndex;
        uint256 toMatch;
        uint256 poolIndex;
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// INTERNAL ///

    /// @notice Matches suppliers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects Aave's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolSupplyIndex;
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstPoolSupplier;
        uint256 remainingToMatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();
        HeapOrdering.HeapArray storage poolSuppliers = suppliersOnPool[_poolToken];
        HeapOrdering.HeapArray storage p2pSuppliers = suppliersInP2P[_poolToken];

        while (
            remainingToMatch > 0 &&
            (firstPoolSupplier = suppliersOnPool[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }

            uint256 poolSupplyBalance = poolSuppliers.getValueOf(firstPoolSupplier);
            uint256 p2pSupplyBalance = p2pSuppliers.getValueOf(firstPoolSupplier);

            vars.toMatch = Math.min(poolSupplyBalance.rayMul(vars.poolIndex), remainingToMatch);
            remainingToMatch -= vars.toMatch;

            poolSupplyBalance -= vars.toMatch.rayDiv(vars.poolIndex);
            p2pSupplyBalance += vars.toMatch.rayDiv(vars.p2pIndex);

            _updateSupplierInDS(_poolToken, firstPoolSupplier, poolSupplyBalance, p2pSupplyBalance);
            emit SupplierPositionUpdated(
                firstPoolSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
    }

    /// @notice Unmatches suppliers' liquidity in peer-to-peer up to the given `_amount` and moves it to Aave.
    /// @dev Note: This function expects Aave's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return unmatched The amount unmatched (in underlying).
    function _unmatchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 unmatched) {
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolSupplyIndex;
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstP2PSupplier;
        uint256 remainingToUnmatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();
        HeapOrdering.HeapArray storage poolSuppliers = suppliersOnPool[_poolToken];
        HeapOrdering.HeapArray storage p2pSuppliers = suppliersInP2P[_poolToken];

        while (
            remainingToUnmatch > 0 &&
            (firstP2PSupplier = suppliersInP2P[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            uint256 poolSupplyBalance = poolSuppliers.getValueOf(firstP2PSupplier);
            uint256 p2pSupplyBalance = p2pSuppliers.getValueOf(firstP2PSupplier);

            vars.toUnmatch = Math.min(p2pSupplyBalance.rayMul(vars.p2pIndex), remainingToUnmatch);
            remainingToUnmatch -= vars.toUnmatch;

            poolSupplyBalance += vars.toUnmatch.rayDiv(vars.poolIndex);
            p2pSupplyBalance -= vars.toUnmatch.rayDiv(vars.p2pIndex);

            _updateSupplierInDS(_poolToken, firstP2PSupplier, poolSupplyBalance, p2pSupplyBalance);
            emit SupplierPositionUpdated(
                firstP2PSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        // Safe unchecked because _amount >= remainingToUnmatch.
        unchecked {
            unmatched = _amount - remainingToUnmatch;
        }
    }

    /// @notice Matches borrowers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects stored indexes to have been updated.
    /// @param _poolToken The address of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstPoolBorrower;
        uint256 remainingToMatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();
        HeapOrdering.HeapArray storage poolBorrowers = borrowersOnPool[_poolToken];
        HeapOrdering.HeapArray storage p2pBorrowers = borrowersInP2P[_poolToken];

        while (
            remainingToMatch > 0 &&
            (firstPoolBorrower = borrowersOnPool[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            uint256 poolBorrowBalance = poolBorrowers.getValueOf(firstPoolBorrower);
            uint256 p2pBorrowBalance = p2pBorrowers.getValueOf(firstPoolBorrower);

            vars.toMatch = Math.min(poolBorrowBalance.rayMul(vars.poolIndex), remainingToMatch);
            remainingToMatch -= vars.toMatch;

            poolBorrowBalance -= vars.toMatch.rayDiv(vars.poolIndex);
            p2pBorrowBalance += vars.toMatch.rayDiv(vars.p2pIndex);

            _updateBorrowerInDS(_poolToken, firstPoolBorrower, poolBorrowBalance, p2pBorrowBalance);
            emit BorrowerPositionUpdated(
                firstPoolBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
    }

    /// @notice Unmatches borrowers' liquidity in peer-to-peer for the given `_amount` and moves it to Aave.
    /// @dev Note: This function expects and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return unmatched The amount unmatched (in underlying).
    function _unmatchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 unmatched) {
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstP2PBorrower;
        uint256 remainingToUnmatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();
        HeapOrdering.HeapArray storage poolBorrowers = borrowersOnPool[_poolToken];
        HeapOrdering.HeapArray storage p2pBorrowers = borrowersInP2P[_poolToken];

        while (
            remainingToUnmatch > 0 &&
            (firstP2PBorrower = borrowersInP2P[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }

            uint256 poolBorrowBalance = poolBorrowers.getValueOf(firstP2PBorrower);
            uint256 p2pBorrowBalance = p2pBorrowers.getValueOf(firstP2PBorrower);

            vars.toUnmatch = Math.min(p2pBorrowBalance.rayMul(vars.p2pIndex), remainingToUnmatch);
            remainingToUnmatch -= vars.toUnmatch;

            poolBorrowBalance += vars.toUnmatch.rayDiv(vars.poolIndex);
            p2pBorrowBalance -= vars.toUnmatch.rayDiv(vars.p2pIndex);

            _updateBorrowerInDS(_poolToken, firstP2PBorrower, poolBorrowBalance, p2pBorrowBalance);
            emit BorrowerPositionUpdated(
                firstP2PBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        // Safe unchecked because _amount >= remainingToUnmatch.
        unchecked {
            unmatched = _amount - remainingToUnmatch;
        }
    }

    /// @notice Updates the given `_user`'s position in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function _updateSupplierInDS(
        address _poolToken,
        address _user,
        uint256 _onPool,
        uint256 _inP2P
    ) internal {
        HeapOrdering.HeapArray storage marketSuppliersOnPool = suppliersOnPool[_poolToken];

        marketSuppliersOnPool.update(_user, _onPool, maxSortedUsers);
        suppliersInP2P[_poolToken].update(_user, _inP2P, maxSortedUsers);

        uint256 formerValueOnPool = marketSuppliersOnPool.getValueOf(_user);
        if (formerValueOnPool != _onPool && address(rewardsManager) != address(0))
            rewardsManager.updateUserAssetAndAccruedRewards(
                aaveIncentivesController,
                _user,
                _poolToken,
                formerValueOnPool,
                IScaledBalanceToken(_poolToken).scaledTotalSupply()
            );
    }

    /// @notice Updates the given `_user`'s position in the borrower data structures.
    /// @param _poolToken The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function _updateBorrowerInDS(
        address _poolToken,
        address _user,
        uint256 _onPool,
        uint256 _inP2P
    ) internal {
        HeapOrdering.HeapArray storage marketBorrowersOnPool = borrowersOnPool[_poolToken];

        marketBorrowersOnPool.update(_user, _onPool, maxSortedUsers);
        borrowersInP2P[_poolToken].update(_user, _inP2P, maxSortedUsers);

        uint256 formerValueOnPool = marketBorrowersOnPool.getValueOf(_user);
        if (formerValueOnPool != _onPool && address(rewardsManager) != address(0)) {
            address variableDebtTokenAddress = pool
            .getReserveData(market[_poolToken].underlyingToken)
            .variableDebtTokenAddress;
            rewardsManager.updateUserAssetAndAccruedRewards(
                aaveIncentivesController,
                _user,
                variableDebtTokenAddress,
                formerValueOnPool,
                IScaledBalanceToken(variableDebtTokenAddress).scaledTotalSupply()
            );
        }
    }
}
