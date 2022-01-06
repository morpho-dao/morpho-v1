// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";
import "./TestSetup.sol";

import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./SimplePriceOracle.sol";
import "./User.sol";
import "./Attacker.sol";

contract BorrowTest is TestSetup {
    // 2.1 - The user borrows less than the threshold of the given market, the transaction reverts.
    function testFail_borrow_2_1_dai() public {
        uint256 amount = positionsManager.threshold(aDai) - 1;
        borrower1.approve(dai, amount);
        borrower1.borrow(aDai, amount);
    }

    function testFail_borrow_2_1_usdc() public {
        uint256 amount = positionsManager.threshold(aUsdc) - 1;
        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.borrow(aUsdc, to6Decimals(2 * amount));
    }

    // 2.2 - The borrower tries to borrow more than his collateral allows, the transaction reverts.
    function testFail_borrow_2_2() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);

        uint256 maxToBorrow = get_max_to_borrow(
            amount,
            usdc,
            dai,
            SimplePriceOracle(lendingPoolAddressesProvider.getPriceOracle())
        );
        borrower1.borrow(aDai, maxToBorrow + 1);
    }

    // Should be able to borrow more ERC20 after already having borrowed ERC20
    function test_multiple_borrow() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(4 * amount));
        borrower1.supply(aUsdc, to6Decimals(4 * amount));

        borrower1.borrow(aDai, amount);
        borrower1.borrow(aDai, amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        marketsManager.updateRates(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(2 * amount, normalizedVariableDebt);
        assertEq(onPool, expectedOnPool);
    }

    // 2.3 - There are no available suppliers: all of the borrowed amount is onPool.
    function test_borrow_2_3(uint256 _amount) public {
        _amount = range(_amount, aDai);

        borrower1.approve(usdc, to6Decimals(2 * _amount));
        borrower1.supply(aUsdc, to6Decimals(2 * _amount));
        borrower1.borrow(aDai, _amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        marketsManager.updateRates(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(_amount, normalizedVariableDebt);

        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    // 2.4 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is inP2P.
    function test_borrow_2_4(uint256 _amount) public {
        _amount = range(_amount, aDai, 1);

        supplier1.approve(dai, _amount);
        supplier1.supply(aDai, _amount);

        borrower1.approve(usdc, to6Decimals(_amount * 2));
        borrower1.supply(aUsdc, to6Decimals(_amount * 2));
        borrower1.borrow(aDai, _amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedInP2P = p2pUnitToUnderlying(supplyInP2P, p2pExchangeRate);
        assertEq(expectedInP2P, _amount, "Supplier1 supply in P2P");

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPool, 0, "Borrower1 borrow on pool");
        assertEq(inP2P, supplyInP2P, "Borrower1 borrow in P2P");
    }

    // 2.5 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity.
    // Borrower inP2P is equal to the supplier previous amount onPool, the rest is set onPool.
    function test_borrow_2_5(uint256 _amount) public {
        _amount = range(_amount, aDai, 4);

        supplier1.approve(dai, _amount);
        supplier1.supply(aDai, _amount);

        borrower1.approve(usdc, to6Decimals(4 * _amount));
        borrower1.supply(aUsdc, to6Decimals(4 * _amount));
        uint256 borrowAmount = _amount * 2;
        borrower1.borrow(aDai, borrowAmount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(inP2P, supplyInP2P, "Borrower1 borrow in P2P");

        marketsManager.updateRates(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(_amount, normalizedVariableDebt);

        assertEq(onPool, expectedOnPool, "Borrower1 borrow on pool");
    }

    // 2.6 - There are NMAX (or less) supplier that match the borrowed amount, everything is inP2P after NMAX (or less) match.
    function test_borrow_2_6(uint256 _amount) public {
        marketsManager.setMaxNumberOfUsersInTree(3);
        uint256 nmax = positionsManager.NMAX();
        _amount = range(_amount, aDai, 2 * nmax);

        // NEEDS TO BE CHANGED TO NMAX
        for (uint256 i = 0; i < suppliers.length; i++) {
            suppliers[i].approve(dai, _amount);
            suppliers[i].supply(aDai, _amount);
        }

        uint256 totalAmount = _amount * suppliers.length;
        borrower1.approve(usdc, to6Decimals(2 * totalAmount));
        borrower1.supply(aUsdc, to6Decimals(2 * totalAmount));
        borrower1.borrow(aDai, totalAmount);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        for (uint256 i = 0; i < suppliers.length; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));

            uint256 expectedInP2P2 = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P2, _amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(inP2P, totalInP2P);
        assertEq(onPool, 0);
    }

    // 2.7 - The NMAX biggest supplier don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set onPool.
    // ⚠️ most gas expensive borrow scenario.
    function test_borrow_2_7(uint256 _amount) public {
        marketsManager.setMaxNumberOfUsersInTree(3);
        uint256 nmax = positionsManager.NMAX();
        _amount = range(_amount, aDai, 4 * nmax);

        for (uint256 i = 0; i < suppliers.length; i++) {
            suppliers[i].approve(dai, _amount);
            suppliers[i].supply(aDai, _amount);
        }

        uint256 totalAmount = _amount * suppliers.length;
        borrower1.approve(usdc, to6Decimals(4 * totalAmount));
        borrower1.supply(aUsdc, to6Decimals(4 * totalAmount));
        borrower1.borrow(aDai, totalAmount * 2);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

        for (uint256 i = 0; i < suppliers.length; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P2 = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P2, _amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        uint256 expectedOnPool = underlyingToAdUnit(totalAmount, normalizedVariableDebt);

        assertEq(inP2P, totalInP2P);
        assertEq(onPool, expectedOnPool);
    }

    // ----------

    function get_max_to_borrow(
        uint256 _collateralInUnderlying,
        address _suppliedAsset,
        address _borrowedAsset,
        SimplePriceOracle _oracle
    ) internal view returns (uint256) {
        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(_borrowedAsset);
        uint256 maxToBorrow = (((((_collateralInUnderlying *
            _oracle.getAssetPrice(_suppliedAsset)) / 10**ERC20(_suppliedAsset).decimals()) *
            10**ERC20(_borrowedAsset).decimals()) / _oracle.getAssetPrice(_borrowedAsset)) *
            liquidationThreshold) / PERCENT_BASE;
        return maxToBorrow;
    }
}
