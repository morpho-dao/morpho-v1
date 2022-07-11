// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./DumbOracle.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract IncentivesVault {
    using SafeTransferLib for ERC20;

    address public immutable morphoToken;
    address public immutable morpho;
    address public immutable oracle;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant BONUS = 1_000;

    constructor(
        address _morpho,
        address _morphoToken,
        address _oracle
    ) {
        morpho = _morpho;
        morphoToken = _morphoToken;
        oracle = _oracle;
    }

    function convertCompToMorphoTokens(address _to, uint256 _amount) external {
        require(msg.sender == morpho, "!morpho");
        ERC20(COMP).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountOut = (IOracle(oracle).consult(_amount) * (MAX_BASIS_POINTS + BONUS)) /
            MAX_BASIS_POINTS;
        ERC20(morphoToken).transfer(_to, amountOut);
    }
}
