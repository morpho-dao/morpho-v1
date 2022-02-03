// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IMatchingEngineForAave.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IRewardsManager.sol";
import "./MatchingEngineForAave.sol";

/// @title PositionsManagerForAave
/// @dev Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
contract PositionsManagerForAave is ReentrancyGuard {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /// Enums ///

    uint8 public SUPPLIERS_IN_P2P = 0;
    uint8 public SUPPLIERS_ON_POOL = 1;
    uint8 public BORROWERS_IN_P2P = 2;
    uint8 public BORROWERS_ON_POOL = 3;

    /// Structs ///

    struct AssetLiquidityData {
        uint256 collateralValue; // The collateral value of the asset (in ETH).
        uint256 maxDebtValue; // The maximum possible debt value of the asset (in ETH).
        uint256 debtValue; // The debt value of the asset (in ETH).
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 underlyingPrice; // The price of the token (in ETH).
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
    }

    struct LiquidateVars {
        uint256 debtValue; // The debt value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        address tokenBorrowedAddress; // The address of the borrowed asset.
        address tokenCollateralAddress; // The address of the collateral asset.
        uint256 borrowedPrice; // The price of the asset borrowed (in ETH).
        uint256 collateralPrice; // The price of the collateral asset (in ETH).
        uint256 borrowBalance; // Total borrow balance of the user for a given asset (in underlying).
        uint256 supplyBalance; // The total of collateral of the user (in underlying).
        uint256 amountToSeize; // The amount of collateral the liquidator can seize (in underlying).
        uint256 liquidationBonus; // The liquidation bonus on Aave.
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The collateral token unit considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
    }

    struct LiquidityData {
        uint256 collateralValue; // The collateral value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        uint256 debtValue; // The debt value (in ETH).
    }

    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50 % in basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.
    mapping(address => uint256) public capValue; // Caps above which suppliers cannot add more liquidity.

    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.

    IMarketsManagerForAave public marketsManagerForAave;
    IAaveIncentivesController public aaveIncentivesController;
    IRewardsManager public rewardsManager;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;
    IProtocolDataProvider public dataProvider;
    MatchingEngineForAave public matchingEngineForAave;
    address public treasuryVault;

    /// Events ///

    /// @dev Emitted when a supply happens.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update (in underlying).
    /// @param _balanceInP2P The supply balance in P2P after update (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    event Supplied(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint16 indexed _referralCode
    );

    /// @dev Emitted when a withdrawal happens.
    /// @param _user The address of the withdrawer.
    /// @param _poolTokenAddress The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event Withdrawn(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @dev Emitted when a borrow happens.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    event Borrowed(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint16 indexed _referralCode
    );

    /// @dev Emitted when a repay happens.
    /// @param _user The address of the repayer.
    /// @param _poolTokenAddress The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event Repaid(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @dev Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidatee The address of the liquidatee.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenBorrowedAddress The address of the borrowed asset.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    /// @param _poolTokenCollateralAddress The address of the collateral asset seized.
    event Liquidated(
        address indexed _liquidator,
        address indexed _liquidatee,
        uint256 _amountRepaid,
        address _poolTokenBorrowedAddress,
        uint256 _amountSeized,
        address _poolTokenCollateralAddress
    );

    /// @dev Emitted when the `lendingPool` is updated on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolUpdated(address _lendingPoolAddress);

    /// @dev Emitted the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address _newTreasuryVaultAddress);

    /// @dev Emitted the address of the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address _newRewardsManagerAddress);

    /// @dev Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address _aaveIncentivesController);

    /// @dev Emitted when a threshold of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the threshold.
    event ThresholdSet(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a cap value of a market is set.
    /// @param _poolTokenAddress The address of the market to set.
    /// @param _newValue The new value of the cap.
    event CapValueSet(address _poolTokenAddress, uint256 _newValue);

    /// @dev Emitted when the DAO claims fees.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of underlying token claimed.
    event FeesClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @dev Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @dev Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address _user, uint256 _amountClaimed);

    /// Errors ///

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// @notice Thrown when only the markets manager can call the function.
    error OnlyMarketsManager();

    /// @notice Thrown when only the markets manager's owner can call the function.
    error OnlyMarketsManagerOwner();

    /// @notice Thrown when the supply is above the cap value.
    error SupplyAboveCapValue();

    /// @notice Thrown when the debt value is not above the maximum debt value.
    error DebtValueNotAboveMax();

    /// @notice Thrown when the amount of collateral to seize is above the collateral amount.
    error ToSeizeAboveCollateral();

    /// @notice Thrown when the amount is not above the threshold.
    error AmountNotAboveThreshold();

    /// @notice Thrown when the amount repaid during the liquidation is above what is allowed to be repaid.
    error AmountAboveWhatAllowedToRepay();

    /// Modifiers ///

    /// @dev Prevents a user to access a market not created yet.
    /// @param _poolTokenAddress The address of the market.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!marketsManagerForAave.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        _;
    }

    /// @dev Prevents a user to supply or borrow less than threshold.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amount The amount of token (in underlying).
    modifier isAboveThreshold(address _poolTokenAddress, uint256 _amount) {
        if (_amount < threshold[_poolTokenAddress]) revert AmountNotAboveThreshold();
        _;
    }

    /// @dev Prevents a user to call function only allowed for the `marketsManagerForAave`.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManagerForAave)) revert OnlyMarketsManager();
        _;
    }

    /// @dev Prevents a user to call function only allowed for `marketsManagerForAave`'s owner.
    modifier onlyMarketsManagerOwner() {
        if (msg.sender != marketsManagerForAave.owner()) revert OnlyMarketsManagerOwner();
        _;
    }

    /// Constructor ///

    /// @dev Constructs the PositionsManagerForAave contract.
    /// @param _marketsManager The address of the aave `marketsManager`.
    /// @param _lendingPoolAddressesProvider The address of the `addressesProvider`.
    constructor(address _marketsManager, address _lendingPoolAddressesProvider) {
        marketsManagerForAave = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        matchingEngineForAave = new MatchingEngineForAave(address(this), _marketsManager);
    }

    /// @dev Updates the `lendingPool` and the `dataProvider`.
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
    }

    /// @dev Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController)
        external
        onlyMarketsManagerOwner
    {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @dev Sets the threshold of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newThreshold The new threshold.
    function setThreshold(address _poolTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_poolTokenAddress] = _newThreshold;
        emit ThresholdSet(_poolTokenAddress, _newThreshold);
    }

    /// @dev Sets the max cap of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newCapValue The new threshold.
    function setCapValue(address _poolTokenAddress, uint256 _newCapValue)
        external
        onlyMarketsManager
    {
        capValue[_poolTokenAddress] = _newCapValue;
        emit CapValueSet(_poolTokenAddress, _newCapValue);
    }

    /// @dev Sets the `_newTreasuryVaultAddress`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyMarketsManagerOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @dev Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyMarketsManagerOwner {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @dev Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        onlyMarketsManagerOwner
        isMarketCreated(_poolTokenAddress)
    {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.transfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @dev Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    function claimRewards(address[] calldata _assets) external {
        uint256 amountToClaim = rewardsManager.claimRewards(_assets, type(uint256).max, msg.sender);
        if (amountToClaim > 0) {
            uint256 amountClaimed = aaveIncentivesController.claimRewards(
                _assets,
                amountToClaim,
                msg.sender
            );
            emit RewardsClaimed(msg.sender, amountClaimed);
        }
    }

    /// @dev Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        if (capValue[_poolTokenAddress] != type(uint256).max)
            _checkCapValue(_poolTokenAddress, underlyingToken, msg.sender, _amount);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Aave, Morpho matches the supplier in P2P with them as much as possible */
        if (
            matchingEngineForAave.getHead(_poolTokenAddress, BORROWERS_ON_POOL) != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            remainingToSupplyToPool -= _supplyPositionToP2P(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough borrowers waiting on Aave to match all the tokens supplied, the rest is supplied to Aave */
        if (remainingToSupplyToPool > 0)
            _supplyPositionToPool(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                remainingToSupplyToPool
            );

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Aave, Morpho matches the borrower in P2P with them as much as possible */
        if (
            matchingEngineForAave.getHead(_poolTokenAddress, SUPPLIERS_ON_POOL) != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            remainingToBorrowOnPool -= _borrowPositionFromP2P(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough suppliers waiting on Aave to match all the tokens borrowed, the rest is borrowed from Aave */
        if (remainingToBorrowOnPool > 0)
            _borrowPositionFromPool(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                remainingToBorrowOnPool
            );

        underlyingToken.safeTransfer(msg.sender, _amount);
        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Withdraws underlying tokens in a specific market.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole balance is withdrawn.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Withdraw all
        if (_amount == type(uint256).max) {
            _amount = _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            );
        }

        _withdraw(_poolTokenAddress, _amount, msg.sender, msg.sender);
    }

    /// @dev Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole debt is repaid.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Repay all
        if (_amount == type(uint256).max) {
            _amount = _getUserBorrowBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            );
        }

        _repay(_poolTokenAddress, msg.sender, _amount);
    }

    /// @dev Allows someone to liquidate a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying).
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();

        LiquidateVars memory vars;
        (vars.debtValue, vars.maxDebtValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        if (vars.debtValue <= vars.maxDebtValue) revert DebtValueNotAboveMax();

        IAToken poolTokenBorrowed = IAToken(_poolTokenBorrowedAddress);
        vars.tokenBorrowedAddress = poolTokenBorrowed.UNDERLYING_ASSET_ADDRESS();

        vars.borrowBalance = _getUserBorrowBalanceInOf(
            _poolTokenBorrowedAddress,
            _borrower,
            vars.tokenBorrowedAddress
        );

        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Aave. Liquidator cannot repay more than part of the debt (cf close factor on Aave).

        _repay(_poolTokenBorrowedAddress, _borrower, _amount);

        IAToken poolTokenCollateral = IAToken(_poolTokenCollateralAddress);
        vars.tokenCollateralAddress = poolTokenCollateral.UNDERLYING_ASSET_ADDRESS();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        vars.borrowedPrice = oracle.getAssetPrice(vars.tokenBorrowedAddress); // In ETH
        vars.collateralPrice = oracle.getAssetPrice(vars.tokenCollateralAddress); // In ETH

        (vars.collateralReserveDecimals, , , vars.liquidationBonus, , , , , , ) = dataProvider
        .getReserveConfigurationData(vars.tokenCollateralAddress);
        (vars.borrowedReserveDecimals, , , , , , , , , ) = dataProvider.getReserveConfigurationData(
            vars.tokenBorrowedAddress
        );
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        // Calculate the amount of collateral to seize (cf Aave):
        // seizeAmount = repayAmount * liquidationBonus * borrowedPrice * collateralTokenUnit / (collateralPrice * borrowedTokenUnit)
        vars.amountToSeize =
            (_amount * vars.borrowedPrice * vars.collateralTokenUnit * vars.liquidationBonus) /
            (vars.borrowedTokenUnit * vars.collateralPrice * MAX_BASIS_POINTS); // Same mechanism as aave. The collateral amount to seize is given.

        vars.supplyBalance = _getUserSupplyBalanceInOf(
            _poolTokenCollateralAddress,
            _borrower,
            vars.tokenCollateralAddress
        );

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        _withdraw(_poolTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender);
        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            vars.amountToSeize,
            _poolTokenCollateralAddress
        );
    }

    /// @dev Returns the collateral value, debt value and max debt value of a given user (in ETH).
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user (in ETH).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum possible debt value of the user (in ETH).
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            collateralValue += assetData.collateralValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
        }
    }

    /// @dev Returns the maximum amount available for withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        LiquidityData memory data;
        AssetLiquidityData memory assetData;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.maxDebtValue += assetData.maxDebtValue;
        data.debtValue += assetData.debtValue;

        // Not possible to withdraw nor borrow
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = ((data.maxDebtValue - data.debtValue) *
            assetData.tokenUnit) / assetData.underlyingPrice;

        withdrawable = Math.min(
            (differenceInUnderlying * MAX_BASIS_POINTS) / assetData.liquidationThreshold,
            (assetData.collateralValue * assetData.tokenUnit) / assetData.underlyingPrice
        );
        borrowable = differenceInUnderlying;
    }

    /// Public ///

    /// @dev Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        IPriceOracleGetter oracle
    ) public view returns (AssetLiquidityData memory assetData) {
        // Compute the current debt amount (in underlying)
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        assetData.debtValue = _getUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        // Compute the current collateral amount (in underlying)
        assetData.collateralValue = _getUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH
        (uint256 reserveDecimals, , uint256 liquidationThreshold, , , , , , , ) = dataProvider
        .getReserveConfigurationData(underlyingAddress);
        assetData.liquidationThreshold = liquidationThreshold;
        assetData.tokenUnit = 10**reserveDecimals;

        // Then, convert values to ETH
        assetData.collateralValue =
            (assetData.collateralValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.maxDebtValue =
            (assetData.collateralValue * liquidationThreshold) /
            MAX_BASIS_POINTS;
        assetData.debtValue =
            (assetData.debtValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// Internal ///

    /// @dev Implements withdraw logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        _checkUserLiquidity(_supplier, _poolTokenAddress, _amount, 0);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Aave */
        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0)
            remainingToWithdraw -= _withdrawPositionFromPool(
                poolToken,
                underlyingToken,
                _supplier,
                remainingToWithdraw
            );

        /* If there remains some tokens to withdraw, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToWithdraw > 0)
            _withdrawPositionFromP2P(poolToken, underlyingToken, _supplier, remainingToWithdraw);

        underlyingToken.safeTransfer(_receiver, _amount);
        emit Withdrawn(
            _supplier,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_receiver].onPool,
            supplyBalanceInOf[_poolTokenAddress][_receiver].inP2P
        );
    }

    /// @dev Implements repay logic.
    /// @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();

        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Aave */
        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0)
            remainingToRepay -= _repayPositionToPool(
                poolToken,
                underlyingToken,
                _user,
                remainingToRepay
            );

        /* If there remains some tokens to repay, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToRepay > 0)
            _repayPositionToP2P(poolToken, underlyingToken, _user, remainingToRepay);

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    /// @dev Supplies `_amount` for a `_user` on a specific market to the pool.
    /// @param _poolToken The pool token of the market the user wants to supply to.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _supplyPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        supplyBalanceInOf[poolTokenAddress][_user].onPool += _amount.divWadByRay(normalizedIncome); // Scaled Balance
        matchingEngineForAave.updateSuppliers(poolTokenAddress, _user);
        _supplyERC20ToPool(_underlyingToken, _amount); // Revert on error
    }

    /// @dev Supplies up to `_amount` for a `_user` on a specific market to P2P.
    /// @param _poolToken The pool token of the market the user wants to supply to.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return matched The amount matched by the borrowers waiting on Pool.
    function _supplyPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );
        matched = matchingEngineForAave.matchBorrowers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            supplyBalanceInOf[poolTokenAddress][_user].inP2P += matched.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            matchingEngineForAave.updateSuppliers(poolTokenAddress, _user);
        }
    }

    /// @dev Borrows `_amount` for `_user` from pool.
    /// @param _poolToken The pool token of the market the user wants to borrow from.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _borrowPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        borrowBalanceInOf[poolTokenAddress][_user].onPool += _amount.divWadByRay(
            normalizedVariableDebt
        ); // In adUnit
        matchingEngineForAave.updateBorrowers(poolTokenAddress, _user);
        _borrowERC20FromPool(_underlyingToken, _amount);
    }

    /// @dev Borrows up to `_amount` for `_user` from P2P.
    /// @param _poolToken The pool token of the market the user wants to borrow from.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return matched The amount matched by the suppliers waiting on Pool.
    function _borrowPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );
        matched = matchingEngineForAave.matchSuppliers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            borrowBalanceInOf[poolTokenAddress][_user].inP2P += matched.divWadByRay(
                borrowP2PExchangeRate
            ); // In p2pUnit
            matchingEngineForAave.updateBorrowers(poolTokenAddress, _user);
        }
    }

    /// @dev Withdraws `_amount` of the position of a `_user` on a specific market.
    /// @param _poolToken The pool token of the market the user wants to withdraw from.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return withdrawnInUnderlying The amount withdrawn from the pool.
    function _withdrawPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 withdrawnInUnderlying) {
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 onPoolSupply = supplyBalanceInOf[poolTokenAddress][_user].onPool;
        uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
        withdrawnInUnderlying = Math.min(
            Math.min(onPoolSupplyInUnderlying, _amount),
            _poolToken.balanceOf(address(this))
        );

        supplyBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
            onPoolSupply,
            withdrawnInUnderlying.divWadByRay(normalizedIncome)
        ); // In poolToken
        matchingEngineForAave.updateSuppliers(poolTokenAddress, _user);
        if (withdrawnInUnderlying > 0)
            _withdrawERC20FromPool(_underlyingToken, withdrawnInUnderlying); // Revert on error
    }

    /// @dev Withdraws `_amount` from the position of a `_user` in P2P.
    /// @param _poolToken The pool token of the market the user wants to withdraw from.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _withdrawPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );

        supplyBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
            supplyBalanceInOf[poolTokenAddress][_user].inP2P,
            _amount.divWadByRay(supplyP2PExchangeRate)
        ); // In p2pUnit
        matchingEngineForAave.updateSuppliers(poolTokenAddress, _user);
        uint256 matchedSupply = matchingEngineForAave.matchSuppliers(
            _poolToken,
            _underlyingToken,
            _amount
        );

        // We break some P2P credit lines the supplier had with borrowers and fallback on Aave.
        if (_amount > matchedSupply)
            matchingEngineForAave.unmatchBorrowers(poolTokenAddress, _amount - matchedSupply); // Revert on error
    }

    /// @dev Repays `_amount` of the position of a `_user` on pool.
    /// @param _poolToken The pool token of the market the user wants to repay a position to.
    /// @param _underlyingToken The underlying token of the market to repay a position to.
    /// @param _user The address of the user.
    /// @param _amount The amount of tokens to repay (in underlying).
    /// @return repaidInUnderlying The amount repaid to the pool.
    function _repayPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 repaidInUnderlying) {
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 borrowedOnPool = borrowBalanceInOf[poolTokenAddress][_user].onPool;
        uint256 borrowedOnPoolInUnderlying = borrowedOnPool.mulWadByRay(normalizedVariableDebt);
        repaidInUnderlying = Math.min(borrowedOnPoolInUnderlying, _amount);

        borrowBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
            borrowedOnPool,
            repaidInUnderlying.divWadByRay(normalizedVariableDebt)
        ); // In adUnit
        matchingEngineForAave.updateBorrowers(poolTokenAddress, _user);
        if (repaidInUnderlying > 0)
            _repayERC20ToPool(_underlyingToken, repaidInUnderlying, normalizedVariableDebt); // Revert on error
    }

    /// @dev Repays `_amount` of the position of a `_user` in P2P.
    /// @param _poolToken The pool token of the market the user wants to repay a position to.
    /// @param _underlyingToken The underlying token of the market to repay a position to.
    /// @param _user The address of user.
    /// @param _amount The amount of token (in underlying).
    function _repayPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );

        borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
            borrowBalanceInOf[poolTokenAddress][_user].inP2P,
            _amount.divWadByRay(borrowP2PExchangeRate)
        ); // In p2pUnit
        matchingEngineForAave.updateBorrowers(poolTokenAddress, _user);
        uint256 matchedBorrow = matchingEngineForAave.matchBorrowers(
            _poolToken,
            _underlyingToken,
            _amount
        );

        // We break some P2P credit lines the borrower had with suppliers and fallback on Aave.
        if (_amount > matchedBorrow)
            matchingEngineForAave.unmatchSuppliers(poolTokenAddress, _amount - matchedBorrow); // Revert on error
    }

    /// @dev Supplies undelrying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(IERC20 _underlyingToken, uint256 _amount) public {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(IERC20 _underlyingToken, uint256 _amount) public {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(IERC20 _underlyingToken, uint256 _amount) public {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) public {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        (, , address variableDebtToken) = dataProvider.getReserveTokensAddresses(
            address(_underlyingToken)
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)).mulWadByRay(
                _normalizedVariableDebt
            )
        );
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }

    /// @dev Checks that the total supply of `supplier` is below the cap on a specific market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @param _underlyingToken The underlying token of the market.
    /// @param _supplier The address of the _supplier to check.
    /// @param _amount The amount to add to the current supply.
    function _checkCapValue(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal view {
        uint256 totalSuppliedInUnderlying = _getUserSupplyBalanceInOf(
            _poolTokenAddress,
            _supplier,
            address(_underlyingToken)
        );

        if (totalSuppliedInUnderlying + _amount > capValue[_poolTokenAddress])
            revert SupplyAboveCapValue();
    }

    ///@dev Enters the user into the market if not already there.
    ///@param _user The address of the user to update.
    ///@param _poolTokenAddress The address of the market to check.
    function _handleMembership(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }

    /// @dev Checks whether the user can borrow/withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    function _checkUserLiquidity(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum debt value possible of the user (in ETH).
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256 debtValue, uint256 maxDebtValue) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            marketsManagerForAave.updateRates(poolTokenEntered);
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += (_borrowedAmount * assetData.underlyingPrice) / assetData.tokenUnit;
                maxDebtValue -= Math.min(
                    maxDebtValue,
                    (_withdrawnAmount *
                        assetData.underlyingPrice *
                        assetData.liquidationThreshold) / (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
            }
        }
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManagerForAave.supplyP2PExchangeRate(_poolTokenAddress)
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedIncome(_underlyingTokenAddress)
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManagerForAave.borrowP2PExchangeRate(_poolTokenAddress)
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(_underlyingTokenAddress)
            );
    }

    function updateSupplyBalanceInOfOnPool(
        address _poolTokenAddress,
        address _user,
        int256 _amount
    ) external {
        if (_amount > 0) supplyBalanceInOf[_poolTokenAddress][_user].onPool += uint256(_amount);
        else supplyBalanceInOf[_poolTokenAddress][_user].onPool -= uint256(-_amount);
    }

    function updateSupplyBalanceInOfInP2P(
        address _poolTokenAddress,
        address _user,
        int256 _amount
    ) external {
        if (_amount > 0) supplyBalanceInOf[_poolTokenAddress][_user].inP2P += uint256(_amount);
        else supplyBalanceInOf[_poolTokenAddress][_user].inP2P -= uint256(-_amount);
    }

    function updateBorrowBalanceInOfOnPool(
        address _poolTokenAddress,
        address _user,
        int256 _amount
    ) external {
        if (_amount > 0) borrowBalanceInOf[_poolTokenAddress][_user].onPool += uint256(_amount);
        else borrowBalanceInOf[_poolTokenAddress][_user].onPool -= uint256(-_amount);
    }

    function updateBorrowBalanceInOfInP2P(
        address _poolTokenAddress,
        address _user,
        int256 _amount
    ) external {
        if (_amount > 0) borrowBalanceInOf[_poolTokenAddress][_user].inP2P += uint256(_amount);
        else borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= uint256(-_amount);
    }
}
