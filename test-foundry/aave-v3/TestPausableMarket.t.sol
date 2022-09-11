// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    address[] public aDaiArray = [aDai];
    address[] public aAaveArray = [aAave];
    uint256[] public amountArray = [1 ether];

    function testAllMarketsPauseUnpause() public {
        morpho.setIsPausedForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.market(pools[i]);
            assertTrue(isSupplyPaused);
            assertTrue(isBorrowPaused);
            assertTrue(isWithdrawPaused);
            assertTrue(isRepayPaused);
            assertTrue(isLiquidateCollateralPaused);
            assertTrue(isLiquidateBorrowPaused);
        }

        morpho.setIsPausedForAllMarkets(false);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.market(pools[i]);
            assertFalse(isSupplyPaused);
            assertFalse(isBorrowPaused);
            assertFalse(isWithdrawPaused);
            assertFalse(isRepayPaused);
            assertFalse(isLiquidateCollateralPaused);
            assertFalse(isLiquidateBorrowPaused);
        }
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        supplier1.borrow(aUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(aUsdc, toBorrow);

        (, toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        supplier1.withdraw(aDai, 1);

        morpho.claimToTreasury(aDaiArray, amountArray);
    }

    function testShouldDisableAllMarketsWhenGloballyPaused() public {
        morpho.setIsPausedForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            hevm.expectRevert(abi.encodeWithSignature("SupplyPaused()"));
            supplier1.supply(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("BorrowPaused()"));
            supplier1.borrow(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("WithdrawPaused()"));
            supplier1.withdraw(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("RepayPaused()"));
            supplier1.repay(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("LiquidateCollateralPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);
        }
    }

    function testOnlyOwnerShouldDisableSupply() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsSupplyPaused(aDai, true);

        morpho.setIsSupplyPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("SupplyPaused()"));
        supplier1.supply(aDai, amount);
    }

    function testOnlyOwnerShouldDisableBorrow() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsBorrowPaused(aDai, true);

        morpho.setIsBorrowPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("BorrowPaused()"));
        supplier1.borrow(aDai, amount);
    }

    function testOnlyOwnerShouldDisableWithdraw() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsWithdrawPaused(aDai, true);

        morpho.setIsWithdrawPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("WithdrawPaused()"));
        supplier1.withdraw(aDai, amount);
    }

    function testOnlyOwnerShouldDisableRepay() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsRepayPaused(aDai, true);

        morpho.setIsRepayPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("RepayPaused()"));
        supplier1.repay(aDai, amount);
    }

    function testOnlyOwnerShouldDisableLiquidateOnCollateral() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateCollateralPaused(aDai, true);

        morpho.setIsLiquidateCollateralPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateCollateralPaused()"));
        supplier1.liquidate(aUsdc, aDai, address(supplier2), amount);
    }

    function testOnlyOwnerShouldDisableLiquidateOnBorrow() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateBorrowPaused(aDai, true);

        morpho.setIsLiquidateBorrowPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateBorrowPaused()"));
        supplier1.liquidate(aDai, aUsdc, address(supplier2), amount);
    }
}
