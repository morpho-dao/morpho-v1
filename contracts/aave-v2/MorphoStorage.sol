// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IInterestRatesManager.sol";
import "./interfaces/IIncentivesVault.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IEntryPositionsManager.sol";
import "./interfaces/IExitPositionsManager.sol";

import "@morpho/data-structures/contracts/HeapOrdering.sol";
import "./libraries/Types.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title MorphoStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice All storage variables used in Morpho contracts.
abstract contract MorphoStorage is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// GLOBAL STORAGE ///

    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint16 public constant MAX_CLAIMABLE_RESERVE = 9_000; // The max proportion of reserve fee claimable by the DAO at once (90% in basis points).
    uint16 public constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000; // 50% in basis points.
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.
    bytes32 public constant BORROWING_MASK =
        0x5555555555555555555555555555555555555555555555555555555555555555;
    uint256 public constant MAX_NB_OF_MARKETS = 128;
    bytes32 public constant ONE =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    bool public isClaimRewardsPaused; // Whether it's possible to claim rewards or not.
    uint256 public maxSortedUsers; // The max number of users to sort in the data structure.
    Types.MaxGasForMatching public defaultMaxGasForMatching; // The default max gas to consume within loops in matching engine functions.

    /// POSITIONS STORAGE ///

    mapping(address => HeapOrdering.HeapArray) internal suppliersInP2P; // For a given market, the suppliers in peer-to-peer.
    mapping(address => HeapOrdering.HeapArray) internal suppliersOnPool; // For a given market, the suppliers on Aave.
    mapping(address => HeapOrdering.HeapArray) internal borrowersInP2P; // For a given market, the borrowers in peer-to-peer.
    mapping(address => HeapOrdering.HeapArray) internal borrowersOnPool; // For a given market, the borrowers on Aave.
    mapping(address => mapping(address => Types.SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user. aToken -> user -> balances.
    mapping(address => mapping(address => Types.BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user. aToken -> user -> balances.
    mapping(address => bytes32) public userMarkets; // The markets entered by a user as a bitmask.

    /// MARKETS STORAGE ///

    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => uint256) public p2pSupplyIndex; // Current index from supply peer-to-peer unit to underlying (in ray).
    mapping(address => uint256) public p2pBorrowIndex; // Current index from borrow peer-to-peer unit to underlying (in ray).
    mapping(address => Types.PoolIndexes) public poolIndexes; // Last pool index stored.
    mapping(address => Types.Market) public market; // Market information.
    mapping(address => uint256) public p2pSupplyAmount; // Peer-to-peer supply amount (in underlying decimals).
    mapping(address => uint256) public p2pBorrowAmount; // Peer-to-peer borrow amount (in underlying decimals).
    mapping(address => uint256) public p2pSupplyDelta; // Peer-to-peer supply delta (in underlying decimals).
    mapping(address => uint256) public p2pBorrowDelta; // Peer-to-peer borrow delta (in underlying decimals).
    mapping(address => bytes32) public borrowMask; // Borrow mask of the given market, shift left to get the supply mask.

    /// CONTRACTS AND ADDRESSES ///

    IAaveIncentivesController public aaveIncentivesController;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public pool;

    IEntryPositionsManager public entryPositionsManager;
    IExitPositionsManager public exitPositionsManager;
    IInterestRatesManager public interestRatesManager;
    IIncentivesVault public incentivesVault;
    IRewardsManager public rewardsManager;
    address public treasuryVault;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}
