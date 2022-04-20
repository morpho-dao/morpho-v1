// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    function testShouldRevertClaimingZero() public {
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        hevm.expectRevert(PositionsManagerForCompoundEventsErrors.AmountIsZero.selector);
        morphoCompound.claimRewards(cTokens, false);
    }

    function testShouldRevertWhenAccruingRewardsForInvalidCToken() public {
        address[] memory cTokens = new address[](2);
        cTokens[0] = cDai;
        cTokens[1] = dai;

        hevm.expectRevert(RewardsManagerForCompound.InvalidCToken.selector);
        rewardsManager.accrueUserUnclaimedRewards(cTokens, address(supplier1));
    }

    function testShouldClaimRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        uint256 balanceBefore = supplier1.balanceOf(comp);

        (, uint256 onPool) = morphoCompound.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        uint256 index = comptroller.compSupplyState(cDai).index;

        assertEq(userIndex, index, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, false);

        index = comptroller.compSupplyState(cDai).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        uint256 balanceAfter = supplier1.balanceOf(comp);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldGetRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        uint256 index = comptroller.compSupplyState(cDai).index;

        (, uint256 onPool) = morphoCompound.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        hevm.roll(block.number + 1_000);
        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(cTokens, address(supplier1));

        supplier1.claimRewards(cTokens, false);
        index = comptroller.compSupplyState(cDai).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        assertEq(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, to6Decimals(50 ether));

        uint256 index = comptroller.compBorrowState(cUsdc).index;

        (, uint256 onPool) = morphoCompound.borrowBalanceInOf(cUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.compBorrowerIndex(cUsdc, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;
        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        assertEq(userIndex, index, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, false);

        index = comptroller.compBorrowState(cUsdc).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        uint256 balanceAfter = supplier1.balanceOf(comp);

        assertEq(balanceAfter, expectedClaimed, "balance after wrong");
    }

    function testShouldGetRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, to6Decimals(50 ether));

        uint256 index = comptroller.compBorrowState(cUsdc).index;

        (, uint256 onPool) = morphoCompound.borrowBalanceInOf(cUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.compBorrowerIndex(cUsdc, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.roll(block.number + 1_000);

        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(cTokens, address(supplier1));

        supplier1.claimRewards(cTokens, false);
        index = comptroller.compBorrowState(cUsdc).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        assertEq(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimOnSeveralMarkets() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(comp);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        supplier1.claimRewards(cTokens, false);
        uint256 rewardBalanceAfter1 = supplier1.balanceOf(comp);
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = cUsdc;
        supplier1.claimRewards(debtUsdcInArray, false);
        uint256 rewardBalanceAfter2 = supplier1.balanceOf(comp);
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    function testShouldNotBePossibleToClaimRewardsOnOtherMarket() public {
        uint256 toSupply = 100 ether;
        uint256 toSupply2 = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier2.approve(usdc, toSupply2);
        supplier2.supply(cUsdc, toSupply2);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.claimRewards(cTokens, false);
    }

    function testShouldClaimRewardsOnSeveralMarketsAtOnce() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = cDai;
        tokensInArray[1] = cUsdc;

        uint256 unclaimedRewardsForDaiView = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );
        uint256 unclaimedRewardsForDai = rewardsManager.accrueUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );
        assertEq(unclaimedRewardsForDaiView, unclaimedRewardsForDai);

        uint256 allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertEq(allUnclaimedRewards, allUnclaimedRewardsView, "all unclaimed rewards 1");
        assertGt(allUnclaimedRewards, unclaimedRewardsForDai);

        supplier1.claimRewards(tokensInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(comp);

        assertGt(rewardBalanceAfter, 0);

        allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertEq(allUnclaimedRewardsView, allUnclaimedRewards, "all unclaimed rewards 2");
        assertEq(allUnclaimedRewards, 0);
    }

    // TODO: investigate why this test fails.
    function _testUsersShouldClaimRewardsIndependently() public {
        interactWithCompound();
        interactWithMorpho();

        uint256[4] memory balanceBefore;
        balanceBefore[1] = IERC20(comp).balanceOf(address(supplier1));
        balanceBefore[2] = IERC20(comp).balanceOf(address(supplier2));
        balanceBefore[3] = IERC20(comp).balanceOf(address(supplier3));

        hevm.roll(block.number + 1_000);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = cDai;
        tokensInArray[1] = cUsdc;
        supplier1.claimRewards(tokensInArray, false);
        supplier2.claimRewards(tokensInArray, false);
        supplier3.claimRewards(tokensInArray, false);

        uint256[4] memory balanceAfter;
        balanceAfter[1] = IERC20(comp).balanceOf(address(supplier1));
        balanceAfter[2] = IERC20(comp).balanceOf(address(supplier2));
        balanceAfter[3] = IERC20(comp).balanceOf(address(supplier3));

        supplier1.compoundClaimRewards(tokensInArray);
        supplier2.compoundClaimRewards(tokensInArray);
        supplier3.compoundClaimRewards(tokensInArray);

        uint256[4] memory balanceAfterCompound;
        balanceAfterCompound[1] = IERC20(comp).balanceOf(address(supplier1));
        balanceAfterCompound[2] = IERC20(comp).balanceOf(address(supplier2));
        balanceAfterCompound[3] = IERC20(comp).balanceOf(address(supplier3));

        uint256[4] memory claimedFromCompound;
        claimedFromCompound[1] = balanceAfterCompound[1] - balanceAfter[1];
        claimedFromCompound[2] = balanceAfterCompound[2] - balanceAfter[2];
        claimedFromCompound[3] = balanceAfterCompound[3] - balanceAfter[3];

        uint256[4] memory claimedFromMorpho;
        claimedFromMorpho[1] = balanceAfter[1];
        claimedFromMorpho[2] = balanceAfter[2];
        claimedFromMorpho[3] = balanceAfter[3];
        assertEq(claimedFromCompound[1], claimedFromMorpho[1], "claimed rewards 1");
        assertEq(claimedFromCompound[2], claimedFromMorpho[2], "claimed rewards 2");
        assertEq(claimedFromCompound[3], claimedFromMorpho[3], "claimed rewards 3");

        assertGt(balanceAfter[1], balanceBefore[1]);
        assertGt(balanceAfter[2], balanceBefore[2]);
        assertGt(balanceAfter[3], balanceBefore[3]);

        uint256 unclaimedRewards1 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 unclaimedRewards2 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier2)
        );
        uint256 unclaimedRewards3 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier3)
        );

        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);
    }

    function interactWithCompound() internal {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;

        supplier1.compoundSupply(cDai, toSupply);
        supplier1.compoundBorrow(cUsdc, toBorrow);
        supplier2.compoundSupply(cDai, toSupply);
        supplier2.compoundBorrow(cUsdc, toBorrow);
        supplier3.compoundSupply(cDai, toSupply);
        supplier3.compoundBorrow(cUsdc, toBorrow);
    }

    function interactWithMorpho() internal {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;

        supplier1.approve(dai, toSupply);
        supplier2.approve(dai, toSupply);
        supplier3.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);
        supplier2.supply(cDai, toSupply);
        supplier2.borrow(cUsdc, toBorrow);
        supplier3.supply(cDai, toSupply);
        supplier3.borrow(cUsdc, toBorrow);
    }

    function testShouldClaimRewardsAndConvertToMorpkoToken() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        uint256 morphoBalanceBefore = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceBefore = supplier1.balanceOf(comp);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, true);

        uint256 morphoBalanceAfter = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceAfter = supplier1.balanceOf(comp);
        assertGt(morphoBalanceAfter, morphoBalanceBefore);
        assertEq(rewardBalanceBefore, rewardBalanceAfter);
    }
}
