// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./libraries/DelegateCall.sol";
import "./morpho-parts/MorphoGovernance.sol";

/// @title Morpho.
/// @notice Smart contract interacting with Compound to enable P2P supply/borrow positions that can fallback on Compound's pool using pool tokens.
contract Morpho is MorphoGovernance {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;
    using DelegateCall for address;

    /// UPGRADE ///

    /// @notice Initializes the Morpho contract.
    /// @param _interestRates The `interestRates`.
    /// @param _comptroller The `comptroller`.
    /// @param _dustThreshold The `dustThreshold`.
    /// @param _maxGasForMatching The `maxGasForMatching`.
    /// @param _maxSortedUsers The `_maxSortedUsers`.
    /// @param _cEth The cETH address.
    /// @param _weth The wETH address.
    function initialize(
        IInterestRates _interestRates,
        IPositionsManager _positionsManager,
        IComptroller _comptroller,
        uint256 _dustThreshold,
        MaxGasForMatching memory _maxGasForMatching,
        uint256 _maxSortedUsers,
        address _cEth,
        address _weth
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        interestRates = _interestRates;
        positionsManager = _positionsManager;
        comptroller = _comptroller;

        dustThreshold = _dustThreshold;
        maxGasForMatching = _maxGasForMatching;
        maxSortedUsers = _maxSortedUsers;

        cEth = _cEth;
        wEth = _weth;
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPausedOrPartiallyPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        updateP2PIndexes(_poolTokenAddress);

        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.supply.selector,
                _poolTokenAddress,
                _amount,
                maxGasForMatching.supply
            )
        );

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external nonReentrant isMarketCreatedAndNotPausedOrPartiallyPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        updateP2PIndexes(_poolTokenAddress);

        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.supply.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function borrow(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPausedOrPartiallyPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        updateP2PIndexes(_poolTokenAddress);

        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.borrow.selector,
                _poolTokenAddress,
                _amount,
                maxGasForMatching.borrow
            )
        );

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external nonReentrant isMarketCreatedAndNotPausedOrPartiallyPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        updateP2PIndexes(_poolTokenAddress);

        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.borrow.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        if (!userMembership[_poolTokenAddress][msg.sender]) revert UserNotMemberOfMarket();
        updateP2PIndexes(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        _checkUserLiquidity(msg.sender, _poolTokenAddress, toWithdraw, 0);
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.withdraw.selector,
                _poolTokenAddress,
                toWithdraw,
                msg.sender,
                msg.sender,
                maxGasForMatching.withdraw
            )
        );

        emit Withdrawn(
            msg.sender,
            _poolTokenAddress,
            toWithdraw,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        if (!userMembership[_poolTokenAddress][msg.sender]) revert UserNotMemberOfMarket();
        updateP2PIndexes(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.repay.selector,
                _poolTokenAddress,
                msg.sender,
                toRepay,
                maxGasForMatching.repay
            )
        );

        emit Repaid(
            msg.sender,
            _poolTokenAddress,
            toRepay,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    )
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenBorrowedAddress)
        isMarketCreatedAndNotPaused(_poolTokenCollateralAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        if (
            !userMembership[_poolTokenBorrowedAddress][_borrower] ||
            !userMembership[_poolTokenCollateralAddress][_borrower]
        ) revert UserNotMemberOfMarket();
        updateP2PIndexes(_poolTokenBorrowedAddress);
        updateP2PIndexes(_poolTokenCollateralAddress);

        uint256 amountSeized = abi.decode(
            address(positionsManager).functionDelegateCall(
                abi.encodeWithSelector(
                    positionsManager.liquidate.selector,
                    _poolTokenBorrowedAddress,
                    _poolTokenCollateralAddress,
                    _borrower,
                    _amount
                )
            ),
            (uint256)
        );

        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            amountSeized,
            _poolTokenCollateralAddress
        );
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _claimMorphoToken Whether or not to claim Morpho tokens instead of token reward.
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken)
        external
        nonReentrant
    {
        uint256 amountOfRewards = rewardsManager.claimRewards(_cTokenAddresses, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();
        else {
            comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(incentivesVault), amountOfRewards);
                incentivesVault.tradeCompForMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }

    // Allows to receive ETH.
    receive() external payable {}
}
