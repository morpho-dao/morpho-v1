// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsManagerForAave {
    struct Balance {
        uint256 inP2P;
        uint256 onPool;
    }

    function createMarket(address) external returns (uint256[] memory);

    function setNmaxForMatchingEngine(uint16) external;

    function setThreshold(address, uint256) external;

    function setCapValue(address, uint256) external;

    function setTreasuryVault(address) external;

    function putSuppliersOnPool(address) external;

    function putBorrowersOnPool(address) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function borrowBalanceInOf(address, address) external returns (Balance memory);

    function supplyBalanceInOf(address, address) external returns (Balance memory);
}
