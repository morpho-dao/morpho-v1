// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./PositionsUpdatorStorageV1.sol";
import "./libraries/DoubleLinkedList.sol";
import "./interfaces/IPositionsUpdator.sol";

contract PositionsUpdatorV1 is IPositionsUpdator, PositionsUpdatorStorageV1 {
    using DoubleLinkedList for DoubleLinkedList.List;

    /* Modifiers */

    /** @dev Prevents a user to call function allowed for the markets manager.
     */
    modifier onlyPositionsManager() {
        require(msg.sender == address(positionsManager), "only-positions-manager");
        _;
    }

    /* Initializer */

    /** @dev Initializes the proxy contract.
     *  @param _positionsManager The new address of the `positionsManager`.
     */
    function initialize(address _positionsManager) public initializer {
        __Ownable_init();
        positionsManager = IPositionsManager(_positionsManager);
    }

    /* External */

    /** @dev Updates the `maxIterations` number.
     *  @param _maxIterations The new `maxIterations`.
     */
    function updateMaxIterations(uint16 _maxIterations) external override onlyPositionsManager {
        maxIterations = _maxIterations;
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function updateBorrowerPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyPositionsManager
    {
        uint256 onPool = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            borrowersOnPool[_poolTokenAddress].insertSorted(_account, onPool, maxIterations);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, maxIterations);
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function updateSupplierPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyPositionsManager
    {
        uint256 onPool = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            suppliersOnPool[_poolTokenAddress].insertSorted(_account, onPool, maxIterations);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, maxIterations);
    }

    /** @dev Returns the borrower's address on Pool to use.
     *  @param _poolTokenAddress The address of the market.
     *  @return _account The address of the borrower.
     */
    function getBorrowerAccountOnPool(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return borrowersOnPool[_poolTokenAddress].getHead();
    }

    /** @dev Returns the borrower's address in P2P to use.
     *  @param _poolTokenAddress The address of the market.
     *  @return _account The address of the borrower.
     */
    function getBorrowerAccountInP2P(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return borrowersInP2P[_poolTokenAddress].getHead();
    }

    /** @dev Returns the supplier's address on Pool to use.
     *  @param _poolTokenAddress The address of the market.
     *  @return _account The address of the borrower.
     */
    function getSupplierAccountOnPool(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return suppliersOnPool[_poolTokenAddress].getHead();
    }

    /** @dev Returns the borrower's address in P2P to use.
     *  @param _poolTokenAddress The address of the market.
     *  @return _account The address of the borrower.
     */
    function getSupplierAccountInP2P(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return suppliersInP2P[_poolTokenAddress].getHead();
    }

    /* Internal */

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
